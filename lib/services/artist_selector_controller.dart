import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

/// Selección de artistas en curso, con su búsqueda en el catálogo y las
/// sugerencias de artistas similares.
///
/// Cada pantalla crea el suyo. Avisa a sus listeners cuando cambia la
/// selección, los resultados o las sugerencias; el texto de búsqueda se
/// escucha en [searchController].
class ArtistSelectorController extends ChangeNotifier {
  ArtistSelectorController({required this._catalog}) {
    searchController.addListener(_onSearchChanged);
  }

  final MusicCatalogService _catalog;

  static const minArtists = 4;
  static const maxArtists = MusicProfileLimits.maxArtists;
  static const _initialSuggestionSeedLimit = 5;
  static const _maxSuggestions = 20;
  static const _searchDebounce = Duration(milliseconds: 400);

  final searchController = TextEditingController();

  final List<Artist> _selected = [];
  List<Artist> _searchResults = [];
  List<Artist> _suggestions = [];
  final Map<String, List<Artist>> _relatedArtistsByKey = {};
  final Set<String> _loadingRelatedArtistKeys = {};
  List<String> _originalArtistKeys = [];
  String? _preferredSuggestionArtistKey;
  int _suggestionsRevision = 0;

  bool _isSearching = false;
  Timer? _debounce;
  String _lastQuery = '';
  int _searchGeneration = 0;
  bool _disposed = false;

  /// Artistas elegidos, en el orden del ranking.
  List<Artist> get selected => UnmodifiableListView(_selected);
  List<Artist> get searchResults => UnmodifiableListView(_searchResults);
  List<Artist> get suggestions => UnmodifiableListView(_suggestions);
  bool get isSearching => _isSearching;

  /// Cambia cuando las sugerencias se sustituyen por completo, no cuando se
  /// retira una al elegirla.
  int get suggestionsRevision => _suggestionsRevision;

  bool get canContinue => _selected.length >= minArtists;
  int get missingArtists => minArtists - _selected.length;

  /// Si el ranking difiere del aplicado con [restore].
  bool get hasChanges {
    final current = _selected.map(keyOf).toList();
    if (current.length != _originalArtistKeys.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _originalArtistKeys[i]) return true;
    }
    return false;
  }

  bool isSelected(Artist artist) {
    final key = keyOf(artist);
    return _selected.any((a) => keyOf(a) == key);
  }

  /// Identidad con la que se deduplican y comparan los artistas.
  static String keyOf(Artist artist) {
    final normalizedName = _normalizeName(artist.name);
    if (normalizedName.isNotEmpty) return normalizedName;

    final spotifyId = artist.spotifyId?.trim();
    if (spotifyId != null && spotifyId.isNotEmpty) return 'spotify:$spotifyId';

    final imageUrl = artist.imageUrl.trim();
    if (imageUrl.isNotEmpty) return 'image:$imageUrl';

    return 'artist:${identityHashCode(artist)}';
  }

  static List<Artist> _dedupeArtists(
    Iterable<Artist> artists, {
    Set<String> excluding = const {},
  }) {
    final seen = {...excluding};
    final deduped = <Artist>[];
    for (final artist in artists) {
      if (seen.add(keyOf(artist))) deduped.add(artist);
    }
    return deduped;
  }

  static String _normalizeName(String name) => name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Parte de un perfil guardado: lo toma como referencia de [hasChanges] y
  /// carga las sugerencias de sus primeros artistas.
  Future<void> restore(Iterable<Artist> artists) async {
    if (_disposed) return;
    _selected
      ..clear()
      ..addAll(_dedupeArtists(artists.take(maxArtists)));
    _originalArtistKeys = _selected.map(keyOf).toList();
    _preferredSuggestionArtistKey = _selected.isEmpty
        ? null
        : keyOf(_selected.first);
    notifyListeners();
    await _loadSuggestions(
      artistsToFetch: _selected.take(_initialSuggestionSeedLimit),
    );
  }

  /// Añade un artista que no está elegido o quita uno que sí lo está.
  void toggle(Artist artist) {
    final artistKey = keyOf(artist);
    final idx = _selected.indexWhere((a) => keyOf(a) == artistKey);
    if (idx >= 0) {
      _selected.removeWhere((a) => keyOf(a) == artistKey);
      _searchResults = _dedupeArtists(_searchResults);
      if (_preferredSuggestionArtistKey == artistKey) {
        _preferredSuggestionArtistKey = null;
      }
      notifyListeners();
      _refreshSuggestions();
    } else {
      if (_selected.length >= maxArtists) return;
      _suggestions.removeWhere((a) => keyOf(a) == artistKey);
      _add(artist);
    }
  }

  /// Elige la sugerencia en [index] y la retira de las sugerencias.
  void addSuggestion(int index) {
    if (_selected.length >= maxArtists) return;
    _add(_suggestions.removeAt(index));
  }

  void _add(Artist artist) {
    final artistKey = keyOf(artist);
    _selected.add(artist);
    _searchResults.removeWhere((a) => keyOf(a) == artistKey);
    _preferredSuggestionArtistKey = artistKey;
    notifyListeners();
    if (artist.imageUrl.isEmpty) unawaited(_enrichFromCatalog(artist));
    searchController.clear();
    unawaited(_loadSuggestions(artistsToFetch: [artist]));
  }

  void reorder(int oldIndex, int newIndex) {
    final item = _selected.removeAt(oldIndex);
    _selected.insert(newIndex, item);
    notifyListeners();
    _refreshSuggestions();
  }

  /// Vacía la búsqueda y sus resultados.
  void clearSearch() {
    searchController.clear();
    _searchResults = [];
    notifyListeners();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = searchController.text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    final generation = ++_searchGeneration;
    if (query.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }
    _isSearching = true;
    notifyListeners();
    _debounce = Timer(_searchDebounce, () => _search(query, generation));
  }

  Future<void> _search(String query, int generation) async {
    try {
      final results = await _catalog.searchArtists(query, limit: 10);
      if (_disposed || generation != _searchGeneration) return;
      final selectedKeys = _selected.map(keyOf).toSet();
      _searchResults = _dedupeArtists(results, excluding: selectedKeys);
      _isSearching = false;
      notifyListeners();
    } catch (e, st) {
      reportError(e, st).ignore();
      if (_disposed || generation != _searchGeneration) return;
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> _loadSuggestions({
    Iterable<Artist> artistsToFetch = const [],
  }) async {
    if (_selected.isEmpty) {
      _replaceSuggestions(const []);
      return;
    }

    final selectedKeys = _selected.map(keyOf).toSet();
    final missingByKey = <String, Artist>{};
    for (final artist in artistsToFetch) {
      final key = keyOf(artist);
      if (selectedKeys.contains(key) &&
          !_relatedArtistsByKey.containsKey(key) &&
          !_loadingRelatedArtistKeys.contains(key)) {
        missingByKey[key] = artist;
      }
    }

    if (missingByKey.isEmpty) {
      _refreshSuggestions();
      return;
    }

    _loadingRelatedArtistKeys.addAll(missingByKey.keys);
    await Future.wait(
      missingByKey.entries.map((entry) async {
        try {
          final related = await _catalog.getRelatedArtists(entry.value.name);
          _relatedArtistsByKey[entry.key] = related;
        } catch (e, st) {
          // Sin caché: la próxima selección del artista lo vuelve a pedir.
          if (!isRateLimitError(e)) reportError(e, st).ignore();
        } finally {
          _loadingRelatedArtistKeys.remove(entry.key);
        }
      }),
    );
    _refreshSuggestions();
  }

  /// Intercala los similares de cada artista elegido, empezando por el último
  /// añadido, sin repetir ni sugerir artistas ya elegidos.
  void _refreshSuggestions() {
    if (_disposed) return;
    if (_selected.isEmpty) {
      _replaceSuggestions(const []);
      return;
    }

    final orderedSeeds = List<Artist>.from(_selected);
    final preferredKey = _preferredSuggestionArtistKey;
    if (preferredKey != null) {
      final preferredIndex = orderedSeeds.indexWhere(
        (artist) => keyOf(artist) == preferredKey,
      );
      if (preferredIndex > 0) {
        final preferred = orderedSeeds.removeAt(preferredIndex);
        orderedSeeds.insert(0, preferred);
      }
    }

    final relatedLists = orderedSeeds
        .map(
          (artist) => _relatedArtistsByKey[keyOf(artist)] ?? const <Artist>[],
        )
        .where((artists) => artists.isNotEmpty)
        .toList();
    final seen = _selected.map(keyOf).toSet();
    final merged = <Artist>[];
    for (
      var relatedIndex = 0;
      merged.length < _maxSuggestions;
      relatedIndex++
    ) {
      var foundCandidate = false;
      for (final related in relatedLists) {
        if (relatedIndex >= related.length) continue;
        foundCandidate = true;
        final candidate = related[relatedIndex];
        if (seen.add(keyOf(candidate))) merged.add(candidate);
        if (merged.length >= _maxSuggestions) break;
      }
      if (!foundCandidate) break;
    }
    _replaceSuggestions(merged);
  }

  void _replaceSuggestions(List<Artist> suggestions) {
    if (_disposed) return;
    _suggestions = List<Artist>.of(suggestions);
    _suggestionsRevision++;
    notifyListeners();
  }

  /// Completa con el catálogo un artista elegido sin imagen.
  Future<void> _enrichFromCatalog(Artist artist) async {
    try {
      final results = await _catalog.searchArtists(artist.name, limit: 1);
      if (_disposed || results.isEmpty) return;
      final enriched = results.first;
      if (_normalizeName(enriched.name) != _normalizeName(artist.name)) return;
      final idx = _selected.indexWhere((a) => keyOf(a) == keyOf(artist));
      if (idx >= 0) _selected[idx] = enriched;
      final selectedKeys = <String>{};
      _selected.removeWhere((a) => !selectedKeys.add(keyOf(a)));
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }
}
