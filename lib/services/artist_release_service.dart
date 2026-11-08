import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/artist_release.dart';
import 'package:musi_link/utils/firestore_collections.dart';

final RegExp _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');

/// Lanzamientos de los artistas seguidos, mantenidos por
/// `checkArtistReleases` en el backend.
class ArtistReleaseService {
  ArtistReleaseService({required this._firestore});

  final FirebaseFirestore _firestore;

  /// Días que abarca la sección «Novedades», incluido el de hoy.
  static const weekDays = 7;

  // Límite de Firestore para `whereIn`.
  static const _queryBatchSize = 30;

  /// Lanzamientos de los últimos [weekDays] días de [artists], del más
  /// reciente al más antiguo.
  Future<List<ArtistRelease>> fetchWeeklyReleases(
    List<Artist> artists, {
    DateTime? now,
  }) async {
    final followed = followedArtistNames(artists);
    if (followed.isEmpty) return const [];

    final ids = followed.keys.toList(growable: false);
    final recentByArtist = <String, Object?>{};
    for (var index = 0; index < ids.length; index += _queryBatchSize) {
      final batch = ids.sublist(
        index,
        (index + _queryBatchSize).clamp(0, ids.length),
      );
      final snapshot = await _firestore
          .collection(FirestoreCollections.artistReleases)
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      for (final doc in snapshot.docs) {
        recentByArtist[doc.id] = doc.data()['recentReleases'];
      }
    }
    return weeklyReleases(recentByArtist, followed, now ?? DateTime.now());
  }

  /// Artistas con identificador de Spotify, en el orden del perfil.
  @visibleForTesting
  static Map<String, String> followedArtistNames(List<Artist> artists) {
    final followed = <String, String>{};
    for (final artist in artists) {
      final id = artist.spotifyId;
      if (id == null || !_spotifyId.hasMatch(id)) continue;
      followed.putIfAbsent(id, () => artist.name);
    }
    return followed;
  }

  @visibleForTesting
  static List<ArtistRelease> weeklyReleases(
    Map<String, Object?> recentByArtist,
    Map<String, String> artistNames,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.subtract(const Duration(days: weekDays - 1));
    final latest = today.add(const Duration(days: 1));
    final releases = <String, ArtistRelease>{};

    for (final MapEntry(key: artistId, value: name) in artistNames.entries) {
      final recent = recentByArtist[artistId];
      if (recent is! List) continue;
      for (final item in recent) {
        final release = ArtistRelease.tryFromMap(
          item,
          artistId: artistId,
          artistName: name,
        );
        if (release == null ||
            release.releaseDate.isBefore(earliest) ||
            release.releaseDate.isAfter(latest)) {
          continue;
        }
        // Una colaboración entre artistas seguidos aparece una sola vez.
        releases.update(
          release.id,
          (existing) => existing.withArtist(artistId, name),
          ifAbsent: () => release,
        );
      }
    }

    return releases.values.toList()..sort((left, right) {
      final byDate = right.releaseDate.compareTo(left.releaseDate);
      if (byDate != 0) return byDate;
      return right.type.index.compareTo(left.type.index);
    });
  }
}
