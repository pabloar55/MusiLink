import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

// ─── Definición de etapas ────────────────────────────────────────────────────

enum _ProfileStage { basic, good, great, expert }

class _StageConfig {
  const _StageConfig({
    required this.stage,
    required this.minCount,
    required this.maxCount,
    required this.color,
  });
  final _ProfileStage stage;
  final int minCount;
  final int maxCount;
  final Color color;
}

const _stages = [
  _StageConfig(
    stage: _ProfileStage.basic,
    minCount: 0,
    maxCount: 9,
    color: Color(0xFFF59E0B),
  ),
  _StageConfig(
    stage: _ProfileStage.good,
    minCount: 10,
    maxCount: 19,
    color: Color(0xFF84CC16),
  ),
  _StageConfig(
    stage: _ProfileStage.great,
    minCount: 20,
    maxCount: 34,
    color: Color(0xFF22C55E),
  ),
  _StageConfig(
    stage: _ProfileStage.expert,
    minCount: 35,
    maxCount: 50,
    color: Color(0xFF1DB954),
  ),
];

_StageConfig _stageFor(int count) {
  for (final s in _stages.reversed) {
    if (count >= s.minCount) return s;
  }
  return _stages.first;
}

// ─── Barra de progreso ───────────────────────────────────────────────────────

class _ProfileProgressBar extends StatelessWidget {
  const _ProfileProgressBar({required this.count, required this.l10n});

  final int count;
  final AppLocalizations l10n;

  static const _maxCount = 50;

  // Convierte el número de artistas en un progreso visual [0, 1] distribuido uniformemente entre los segmentos.
  static double _toVisualProgress(int count) {
    final current = _stageFor(count);
    final idx = _stages.indexOf(current);
    final range = current.maxCount - current.minCount;
    final within = range > 0 ? (count - current.minCount) / range : 1.0;
    return (idx + within) / _stages.length;
  }

  String _stageLabel(_ProfileStage stage) => switch (stage) {
    _ProfileStage.basic => l10n.artistSelectorStageBasic,
    _ProfileStage.good => l10n.artistSelectorStageGood,
    _ProfileStage.great => l10n.artistSelectorStageGreat,
    _ProfileStage.expert => l10n.artistSelectorStageExpert,
  };

  @override
  Widget build(BuildContext context) {
    final current = _stageFor(count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Row(
                key: ValueKey(current.stage),
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: current.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _stageLabel(current.stage),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: current.color,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$count / $_maxCount',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _toVisualProgress(count)),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, t, _) {
            return Row(
              children: _stages.asMap().entries.map((entry) {
                final i = entry.key;
                final stage = entry.value;
                final isLast = i == _stages.length - 1;
                final isPast =
                    _stages.indexOf(stage) < _stages.indexOf(current);
                // Cada segmento ocupa 1/_stages.length del rango visual total.
                final segFill = (t * _stages.length - i).clamp(0.0, 1.0);

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                          FractionallySizedBox(
                            widthFactor: segFill,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                              height: 6,
                              color: isPast ? current.color : stage.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ArtistSelectorScreen extends ConsumerStatefulWidget {
  const ArtistSelectorScreen({super.key, this.isEditMode = false});

  final bool isEditMode;

  @override
  ConsumerState<ArtistSelectorScreen> createState() =>
      _ArtistSelectorScreenState();
}

class _ArtistSelectorScreenState extends ConsumerState<ArtistSelectorScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  List<Artist> _searchResults = [];
  List<Artist> _suggestions = [];
  final List<Artist> _selected = [];
  GlobalKey<AnimatedListState> _suggestionsListKey = GlobalKey();
  List<String> _originalArtistKeys = [];

  bool _isSearching = false;
  bool _isSaving = false;
  Timer? _debounce;
  String _lastQuery = '';

  static const _minArtists = 4;
  static const _maxArtists = 50;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    if (widget.isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadExistingArtists(),
      );
    }
  }

  Future<void> _loadExistingArtists() async {
    try {
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid == null) return;
      final currentUser = ref.read(currentUserProvider).asData?.value;
      var user = currentUser?.uid == uid ? currentUser : null;
      if (user?.topArtists.isEmpty ?? true) {
        user = await ref
            .read(userServiceProvider)
            .getUser(uid, bypassCache: true);
      }
      if (!mounted || user == null) return;
      final loadedUser = user;
      setState(() {
        _selected.addAll(_dedupeArtists(loadedUser.topArtists));
        _originalArtistKeys = _selected.map(_artistKey).toList();
      });
    } catch (e, st) {
      reportError(e, st).ignore();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query == _lastQuery) return;
    _lastQuery = query;
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final results = await ref
          .read(musicCatalogServiceProvider)
          .searchArtists(query, limit: 20);
      if (!mounted) return;
      final selectedKeys = _selected.map(_artistKey).toSet();
      setState(() {
        _searchResults = _dedupeArtists(results, excluding: selectedKeys);
        _isSearching = false;
      });
    } catch (e, st) {
      reportError(e, st).ignore();
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  Future<void> _loadSuggestions() async {
    if (_selected.isEmpty) return;
    try {
      final service = ref.read(musicCatalogServiceProvider);
      final results = await Future.wait(
        _selected.map((a) => service.getRelatedArtists(a.name)),
      );
      if (!mounted) return;
      final selectedKeys = _selected.map(_artistKey).toSet();
      final seen = {...selectedKeys};
      final merged = <Artist>[];
      for (final list in results) {
        for (final a in list) {
          if (seen.add(_artistKey(a))) {
            merged.add(a);
            if (merged.length >= 20) break;
          }
        }
        if (merged.length >= 20) break;
      }
      setState(() {
        _suggestions = merged;
        _suggestionsListKey = GlobalKey();
      });
    } catch (_) {}
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _selected.removeAt(oldIndex);
      _selected.insert(newIndex, item);
    });
  }

  void _toggleArtist(Artist artist) {
    final artistKey = _artistKey(artist);
    final idx = _selected.indexWhere((a) => _artistKey(a) == artistKey);
    if (idx >= 0) {
      setState(() {
        _selected.removeWhere((a) => _artistKey(a) == artistKey);
        _searchResults = _dedupeArtists(_searchResults);
      });
    } else {
      if (_selected.length >= _maxArtists) return;
      setState(() {
        _selected.add(artist);
        _searchResults.removeWhere((a) => _artistKey(a) == artistKey);
        _suggestions.removeWhere((a) => _artistKey(a) == artistKey);
      });
      if (artist.imageUrl.isEmpty) _enrichFromSpotify(artist);
      _searchController.clear();
    }
    _loadSuggestions();
  }

  static String _artistKey(Artist artist) {
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
      if (seen.add(_artistKey(artist))) deduped.add(artist);
    }
    return deduped;
  }

  static String _normalizeName(String name) => name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _enrichFromSpotify(Artist artist) async {
    try {
      final results = await ref
          .read(musicCatalogServiceProvider)
          .searchArtists(artist.name, limit: 1);
      if (!mounted || results.isEmpty) return;
      final enriched = results.first;
      if (_normalizeName(enriched.name) != _normalizeName(artist.name)) return;
      setState(() {
        final idx = _selected.indexWhere(
          (a) => _artistKey(a) == _artistKey(artist),
        );
        if (idx >= 0) _selected[idx] = enriched;
        final selectedKeys = <String>{};
        _selected.removeWhere((a) => !selectedKeys.add(_artistKey(a)));
      });
    } catch (_) {}
  }

  bool get _hasChanges {
    final current = _selected.map(_artistKey).toList();
    if (current.length != _originalArtistKeys.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != _originalArtistKeys[i]) return true;
    }
    return false;
  }

  void _saveAndPop() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final musicProfileService = ref.read(musicProfileServiceProvider);
    final userService = ref.read(userServiceProvider);
    final container = ProviderScope.containerOf(context);
    final selected = List<Artist>.from(_selected);

    if (mounted) context.pop();

    if (uid == null || selected.length < _minArtists || !_hasChanges) return;
    musicProfileService
        .saveManualArtists(uid, selected)
        .then((_) {
          userService.clearCache();
          container.invalidate(currentUserProvider);
        })
        .catchError((e, StackTrace st) {
          reportError(e, st).ignore();
        });
  }

  Future<void> _save() async {
    if (_selected.length < _minArtists) return;
    setState(() => _isSaving = true);
    try {
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid == null) return;

      await ref
          .read(musicProfileServiceProvider)
          .saveManualArtists(uid, _selected);
      ref.read(userServiceProvider).clearCache();
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      ref.read(appRouterNotifierProvider).setArtistsSelected();
    } catch (e, st) {
      reportError(e, st).ignore();
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.genericError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showSearch = _searchController.text.trim().isNotEmpty;
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: !widget.isEditMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.isEditMode) _saveAndPop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.isEditMode ? 4 : 24,
                  widget.isEditMode ? 8 : 24,
                  24,
                  0,
                ),
                child: Row(
                  children: [
                    if (widget.isEditMode) BackButton(onPressed: _saveAndPop),
                    Text(
                      l10n.artistSelectorTitle,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  widget.isEditMode ? 4 : 8,
                  24,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.artistSelectorSubtitle(_selected.length),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ProfileProgressBar(
                          count: _selected.length,
                          l10n: l10n,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                    TextField(
                      focusNode: _searchFocusNode,
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: l10n.artistSelectorSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchResults = []);
                                },
                              )
                            : null,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_suggestions.isNotEmpty) const SizedBox(height: 10),
                  ],
                ),
              ),
              if (_suggestions.isNotEmpty && !showSearch)
                _buildSuggestedArtistsRow(l10n),

              Expanded(child: _buildArtistContent(l10n, showSearch)),

              if (!widget.isEditMode)
                Visibility(
                  visible: !isKeyboardVisible,
                  maintainState: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed:
                            (_selected.length >= _minArtists && !_isSaving)
                            ? _save
                            : null,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _selected.length >= _minArtists
                                    ? l10n.artistSelectorContinue
                                    : l10n.artistSelectorContinueLocked(
                                        _minArtists - _selected.length,
                                      ),
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtistContent(AppLocalizations l10n, bool showSearch) {
    if (showSearch) return _buildSearchResults(l10n);

    if (_selected.isEmpty) return _buildEmptySelectedState(l10n);

    return _buildRankedList();
  }

  Widget _buildRankedList() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _selected.length,
      onReorderItem: _onReorder,
      itemBuilder: (_, i) => _buildRankedItem(_selected[i], i),
    );
  }

  Widget _buildSearchResults(AppLocalizations l10n) {
    if (_isSearching) {
      return SkeletonShimmer(
        child: ListView.builder(
          itemCount: 8,
          itemBuilder: (_, _) => const SkeletonListTile(),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          l10n.artistSelectorNoResults,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return _artistList(_searchResults);
  }

  Widget _buildEmptySelectedState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          l10n.artistSelectorEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _onSuggestionTap(Artist artist, int index) {
    if (_selected.length >= _maxArtists) return;

    _suggestions.removeAt(index);
    _suggestionsListKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAnimatingChip(artist, animation),
      duration: const Duration(milliseconds: 180),
    );

    setState(() {
      _selected.add(artist);
      _searchResults.removeWhere((a) => _artistKey(a) == _artistKey(artist));
    });
    if (artist.imageUrl.isEmpty) _enrichFromSpotify(artist);
    _searchController.clear();
    _loadSuggestions();
  }

  Widget _buildAnimatingChip(Artist artist, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: SizeTransition(
        sizeFactor: animation,
        axis: Axis.horizontal,
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            label: Text(artist.name),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onPressed: null,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedArtistsRow(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            l10n.artistSelectorSuggested,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: Theme(
            data: Theme.of(context).copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            child: AnimatedList(
              key: _suggestionsListKey,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              initialItemCount: _suggestions.length,
              itemBuilder: (_, i, animation) {
                final artist = _suggestions[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(artist.name),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _onSuggestionTap(artist, i),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankedItem(Artist artist, int index) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey(_artistKey(artist)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.primary,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundImage: artist.imageUrl.isNotEmpty
                ? CachedNetworkImageProvider(artist.imageUrl)
                : null,
            child: artist.imageUrl.isEmpty
                ? const Icon(Icons.person, size: 16)
                : null,
          ),
        ],
      ),
      title: Text(artist.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            onPressed: () => _toggleArtist(artist),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _artistList(List<Artist> artists) {
    return ListView.builder(
      controller: _scrollController,
      itemCount: artists.length,
      itemBuilder: (_, i) {
        final artist = artists[i];
        final isSelected = _selected.any(
          (a) => _artistKey(a) == _artistKey(artist),
        );
        return ListTile(
          visualDensity: const VisualDensity(vertical: -2),
          minVerticalPadding: 2,
          leading: CircleAvatar(
            backgroundImage: artist.imageUrl.isNotEmpty
                ? CachedNetworkImageProvider(artist.imageUrl)
                : null,
            child: artist.imageUrl.isEmpty ? const Icon(Icons.person) : null,
          ),
          title: Text(artist.name),
          subtitle: artist.genres.isNotEmpty
              ? Text(
                  artist.genres.take(3).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: isSelected
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : Icon(
                  Icons.add_circle_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          onTap: () => _toggleArtist(artist),
        );
      },
    );
  }
}
