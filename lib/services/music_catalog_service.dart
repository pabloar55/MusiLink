import 'dart:async';
import 'dart:collection';

import 'package:musi_link/models/artist.dart' as app;
import 'package:musi_link/models/genre.dart';
import 'package:musi_link/models/track.dart' as app;
import 'package:musi_link/services/last_fm_service.dart';
import 'package:musi_link/services/spotify_cloud_service.dart';
import 'package:musi_link/utils/genre_normalizer.dart';

/// Búsqueda de catálogo musical y cálculo local del perfil musical manual.
class MusicCatalogService {
  MusicCatalogService(this._client, this._lastFm, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SpotifyCloudService _client;
  final LastFmService _lastFm;
  final DateTime Function() _now;

  static const _relatedArtistsCacheTtl = Duration(hours: 24);
  static const _emptyRelatedArtistsCacheTtl = Duration(minutes: 5);
  static const _maxRelatedArtistsCacheSize = 200;
  static const _maxConcurrentRelatedArtistRequests = 3;

  final LinkedHashMap<String, ({List<app.Artist> artists, DateTime cachedAt})>
  _relatedArtistsCache = LinkedHashMap();
  final Map<String, Future<List<app.Artist>>> _pendingRelatedArtistRequests =
      {};
  final Queue<Completer<void>> _relatedArtistRequestQueue = Queue();
  int _activeRelatedArtistRequests = 0;

  List<Genre> getTopGenresFromArtists(List<app.Artist> artists, int limit) {
    final genreCount = <String, int>{};
    for (final artist in artists) {
      for (final genre in artist.genres) {
        final normalizedGenre = normalizeGenreName(genre);
        if (normalizedGenre == null) continue;
        genreCount[normalizedGenre] = (genreCount[normalizedGenre] ?? 0) + 1;
      }
    }
    if (genreCount.isEmpty) return [];
    final sorted = genreCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalMentions = sorted.fold<int>(0, (sum, e) => sum + e.value);
    return sorted.take(limit).map((entry) {
      return Genre(
        name: entry.key,
        count: entry.value,
        percentage: (entry.value / totalMentions) * 100,
      );
    }).toList();
  }

  Future<List<app.Track>> searchTracks(String query, {int limit = 10}) =>
      _client.searchTracks(query, limit: limit);

  Future<List<app.Artist>> searchArtists(String query, {int limit = 10}) =>
      _client.searchArtists(query, limit: limit);

  Future<List<app.Artist>> getRelatedArtists(String artistName) {
    final key = _normalizeArtistName(artistName);
    if (key.isEmpty) return Future.value(const []);

    final cached = _relatedArtistsCache[key];
    if (cached != null) {
      final ttl = cached.artists.isEmpty
          ? _emptyRelatedArtistsCacheTtl
          : _relatedArtistsCacheTtl;
      if (_now().difference(cached.cachedAt) < ttl) {
        // Reinsertar actualiza el orden LRU.
        _relatedArtistsCache
          ..remove(key)
          ..[key] = cached;
        return Future.value(cached.artists);
      }
      _relatedArtistsCache.remove(key);
    }

    final pending = _pendingRelatedArtistRequests[key];
    if (pending != null) return pending;

    late final Future<List<app.Artist>> request;
    request =
        _withRelatedArtistRequestSlot(
              () => _lastFm.getSimilarArtists(artistName.trim()),
            )
            .then((artists) {
              final immutableArtists = List<app.Artist>.unmodifiable(artists);
              _relatedArtistsCache.remove(key);
              while (_relatedArtistsCache.length >=
                  _maxRelatedArtistsCacheSize) {
                _relatedArtistsCache.remove(_relatedArtistsCache.keys.first);
              }
              _relatedArtistsCache[key] = (
                artists: immutableArtists,
                cachedAt: _now(),
              );
              return immutableArtists;
            })
            .whenComplete(() {
              if (identical(_pendingRelatedArtistRequests[key], request)) {
                _pendingRelatedArtistRequests.remove(key);
              }
            });
    _pendingRelatedArtistRequests[key] = request;
    return request;
  }

  void clearRelatedArtistsCache() => _relatedArtistsCache.clear();

  Future<T> _withRelatedArtistRequestSlot<T>(
    Future<T> Function() action,
  ) async {
    if (_activeRelatedArtistRequests >= _maxConcurrentRelatedArtistRequests) {
      final ready = Completer<void>();
      _relatedArtistRequestQueue.add(ready);
      await ready.future;
    } else {
      _activeRelatedArtistRequests++;
    }

    try {
      return await action();
    } finally {
      if (_relatedArtistRequestQueue.isNotEmpty) {
        // El hueco se transfiere directamente al siguiente, por lo que el
        // contador de peticiones activas no cambia.
        _relatedArtistRequestQueue.removeFirst().complete();
      } else {
        _activeRelatedArtistRequests--;
      }
    }
  }

  static String _normalizeArtistName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
