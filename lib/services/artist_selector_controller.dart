import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/utils/artist_identity.dart';
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
  // Los similares se piden por nombre, así que se guardan por nombre.
  final Map<String, List<Artist>> _relatedArtistsByName = {};
  final Set<String> _loadingRelatedArtistNames = {};
  List<Artist> _originalArtists = [];
  Artist? _preferredSuggestionArtist;
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

  /// Si el ranking difiere del aplicado con [restore]. Completar un artista
  /// con el catálogo no cuenta como cambio.
  bool get hasChanges {
    if (_selected.length != _originalArtists.length) return true;
    for (var i = 0; i < _selected.length; i++) {
      if (!isSameArtist(_selected[i], _originalArtists[i])) return true;
    }
    return false;
  }

  bool isSelected(Artist artist) =>
      _selected.any((selected) => isSameArtist(selected, artist));

  static List<Artist> _dedupeArtists(
    Iterable<Artist> artists, {
    Iterable<Artist> excluding = const [],
  }) {
    final seen = ArtistIdentitySet(excluding);
    return [
      for (final artist in artists)
        if (seen.add(artist)) artist,
    ];
  }

  static String _relatedArtistsName(Artist artist) =>
      normalizeArtistIdentityName(artist.name);

  /// Parte de un perfil guardado: lo toma como referencia de [hasChanges] y
  /// carga las sugerencias de sus primeros artistas.
  Future<void> restore(Iterable<Artist> artists) async {
    if (_disposed) return;
    _selected
      ..clear()
      ..addAll(_dedupeArtists(artists.take(maxArtists)));
    _originalArtists = List.of(_selected);
    _preferredSuggestionArtist = _selected.firstOrNull;
    notifyListeners();
    await _loadSuggestions(
      artistsToFetch: _selected.take(_initialSuggestionSeedLimit),
    );
  }

  /// Añade un artista que no está elegido o quita uno que sí lo está.
  void toggle(Artist artist) {
    if (isSelected(artist)) {
      _selected.removeWhere((a) => isSameArtist(a, artist));
      _searchResults = _dedupeArtists(_searchResults);
      final preferred = _preferredSuggestionArtist;
      if (preferred != null && isSameArtist(preferred, artist)) {
        _preferredSuggestionArtist = null;
      }
      notifyListeners();
      _refreshSuggestions();
    } else {
      if (_selected.length >= maxArtists) return;
      _suggestions.removeWhere((a) => isSameArtist(a, artist));
      _add(artist);
    }
  }

  /// Elige la sugerencia en [index] y la retira de las sugerencias.
  void addSuggestion(int index) {
    if (_selected.length >= maxArtists) return;
    _add(_suggestions.removeAt(index));
  }

  void _add(Artist artist) {
    _selected.add(artist);
    _searchResults.removeWhere((a) => isSameArtist(a, artist));
    _preferredSuggestionArtist = artist;
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
      _searchResults = _dedupeArtists(results, excluding: _selected);
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

    final selected = ArtistIdentitySet(_selected);
    final missingByName = <String, Artist>{};
    for (final artist in artistsToFetch) {
      final name = _relatedArtistsName(artist);
      if (selected.contains(artist) &&
          !_relatedArtistsByName.containsKey(name) &&
          !_loadingRelatedArtistNames.contains(name)) {
        missingByName[name] = artist;
      }
    }

    if (missingByName.isEmpty) {
      _refreshSuggestions();
      return;
    }

    _loadingRelatedArtistNames.addAll(missingByName.keys);
    await Future.wait(
      missingByName.entries.map((entry) async {
        try {
          final related = await _catalog.getRelatedArtists(entry.value.name);
          _relatedArtistsByName[entry.key] = related;
        } catch (e, st) {
          // Sin caché: la próxima selección del artista lo vuelve a pedir.
          if (!isRateLimitError(e)) reportError(e, st).ignore();
        } finally {
          _loadingRelatedArtistNames.remove(entry.key);
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
    final preferred = _preferredSuggestionArtist;
    if (preferred != null) {
      final preferredIndex = orderedSeeds.indexWhere(
        (artist) => isSameArtist(artist, preferred),
      );
      if (preferredIndex > 0) {
        final preferred = orderedSeeds.removeAt(preferredIndex);
        orderedSeeds.insert(0, preferred);
      }
    }

    final relatedLists = orderedSeeds
        .map(
          (artist) =>
              _relatedArtistsByName[_relatedArtistsName(artist)] ??
              const <Artist>[],
        )
        .where((artists) => artists.isNotEmpty)
        .toList();
    final seen = ArtistIdentitySet(_selected);
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
        if (seen.add(candidate)) merged.add(candidate);
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

  /// Completa con el catálogo un artista elegido sin imagen. Solo acepta el
  /// primer resultado si es el mismo artista: con dos spotifyId decide el id
  /// y, si no, el nombre normalizado, que no puede quedar vacío.
  Future<void> _enrichFromCatalog(Artist artist) async {
    try {
      final results = await _catalog.searchArtists(artist.name, limit: 1);
      if (_disposed || results.isEmpty) return;
      final enriched = results.first;
      if (normalizeArtistIdentityName(artist.name).isEmpty ||
          !isSameArtist(enriched, artist)) {
        return;
      }
      final idx = _selected.indexWhere((a) => isSameArtist(a, artist));
      if (idx >= 0) _selected[idx] = enriched;
      final seen = ArtistIdentitySet();
      _selected.removeWhere((a) => !seen.add(a));
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
