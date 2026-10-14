import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/music_profile_sync_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/providers/user_setup_provider.dart';
import 'package:musi_link/services/artist_selector_controller.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/music_profile_limits.dart';
import 'package:musi_link/widgets/artist_avatar.dart';
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
    maxCount: 5,
    color: Color(0xFFF59E0B),
  ),
  _StageConfig(
    stage: _ProfileStage.good,
    minCount: 6,
    maxCount: 11,
    color: Color(0xFF84CC16),
  ),
  _StageConfig(
    stage: _ProfileStage.great,
    minCount: 12,
    maxCount: 19,
    color: Color(0xFF22C55E),
  ),
  _StageConfig(
    stage: _ProfileStage.expert,
    minCount: 20,
    maxCount: MusicProfileLimits.maxArtists,
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

  static const _maxCount = MusicProfileLimits.maxArtists;

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
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
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
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  late final ArtistSelectorController _selection;
  GlobalKey<AnimatedListState> _suggestionsListKey = GlobalKey();
  int _suggestionsRevision = 0;

  bool _isSaving = false;
  bool _isLeaving = false;
  bool _allowPop = false;

  static const _maxArtists = ArtistSelectorController.maxArtists;

  @override
  void initState() {
    super.initState();
    _selection = ArtistSelectorController(
      catalog: ref.read(musicCatalogServiceProvider),
    )..addListener(_onSelectionChanged);
    _suggestionsRevision = _selection.suggestionsRevision;
    if (widget.isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadExistingArtists(),
      );
    }
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {
      // Unas sugerencias nuevas reconstruyen la lista animada desde cero.
      if (_selection.suggestionsRevision != _suggestionsRevision) {
        _suggestionsRevision = _selection.suggestionsRevision;
        _suggestionsListKey = GlobalKey();
      }
    });
  }

  Future<void> _loadExistingArtists() async {
    try {
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid == null) return;
      final syncCoordinator = ref.read(musicProfileSyncCoordinatorProvider);
      syncCoordinator.resume();
      final pendingArtists = syncCoordinator.pendingArtists(uid);
      if (pendingArtists != null) {
        await _selection.restore(pendingArtists);
        return;
      }
      final currentUser = ref.read(currentUserProvider).asData?.value;
      final cachedUser = currentUser?.uid == uid ? currentUser : null;
      var user = cachedUser;
      try {
        // La referencia de cambios debe ser la última versión confirmada por
        // el servidor, no el provider aún en caché de un guardado anterior.
        user = await ref
            .read(userServiceProvider)
            .getUser(
              uid,
              bypassCache: true,
              serverOnly: true,
              reportErrors: false,
            );
      } catch (e, st) {
        if (cachedUser == null) rethrow;
        reportError(e, st).ignore();
      }
      if (!mounted || user == null) return;
      await _selection.restore(user.topArtists);
    } catch (e, st) {
      reportError(e, st).ignore();
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _popAfterRebuild() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<void> _saveAndPop() async {
    if (_isLeaving) return;
    _isLeaving = true;

    if (!_selection.hasChanges) {
      _popAfterRebuild();
      return;
    }
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) {
      _popAfterRebuild();
      return;
    }

    try {
      await ref
          .read(musicProfileSyncCoordinatorProvider)
          .enqueue(uid, List<Artist>.from(_selection.selected));
    } catch (error, stack) {
      reportError(error, stack).ignore();
    } finally {
      _popAfterRebuild();
    }
  }

  Future<void> _save() async {
    if (!_selection.canContinue) return;
    setState(() => _isSaving = true);
    try {
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid == null) return;

      await ref
          .read(musicProfileServiceProvider)
          .saveManualArtists(List<Artist>.from(_selection.selected));
      if (!mounted || ref.read(firebaseAuthProvider).currentUser?.uid != uid) {
        return;
      }
      ref.read(userServiceProvider).clearCache();
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      ref.read(userSetupControllerProvider).setArtistsSelected();
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
    final showSearch = _selection.searchController.text.trim().isNotEmpty;
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: !widget.isEditMode || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.isEditMode) unawaited(_saveAndPop());
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.isEditMode ? 4 : 24,
                  8,
                  widget.isEditMode ? 24 : 12,
                  0,
                ),
                child: Row(
                  children: [
                    if (widget.isEditMode)
                      _isSaving
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : BackButton(
                              onPressed: () => unawaited(_saveAndPop()),
                            ),
                    Expanded(
                      child: Text(
                        l10n.artistSelectorTitle,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!widget.isEditMode)
                      Visibility(
                        visible: _selection.canContinue,
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: true,
                        child: IconButton(
                          tooltip: l10n.artistSelectorContinue,
                          onPressed: _isSaving ? null : _save,
                          icon: const Icon(Icons.arrow_forward),
                        ),
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
                          l10n.artistSelectorSubtitle(
                            _selection.selected.length,
                            MusicProfileLimits.maxArtists,
                          ),
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ProfileProgressBar(
                          count: _selection.selected.length,
                          l10n: l10n,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                    TextField(
                      focusNode: _searchFocusNode,
                      controller: _selection.searchController,
                      decoration: InputDecoration(
                        hintText: l10n.artistSelectorSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _selection.searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _selection.clearSearch,
                              )
                            : null,
                        filled: true,
                        border: AppTheme.pillInputBorder,
                        enabledBorder: AppTheme.pillInputBorder,
                        focusedBorder: AppTheme.pillInputBorder,
                      ),
                    ),
                    if (_selection.suggestions.isNotEmpty)
                      const SizedBox(height: 10),
                  ],
                ),
              ),
              if (_selection.suggestions.isNotEmpty && !showSearch)
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
                        onPressed: (_selection.canContinue && !_isSaving)
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
                                _selection.canContinue
                                    ? l10n.artistSelectorContinue
                                    : l10n.artistSelectorContinueLocked(
                                        _selection.missingArtists,
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

    if (_selection.selected.isEmpty) return _buildEmptySelectedState(l10n);

    return _buildRankedList();
  }

  Widget _buildRankedList() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _selection.selected.length,
      onReorderItem: _selection.reorder,
      itemBuilder: (_, i) => _buildRankedItem(_selection.selected[i], i),
    );
  }

  Widget _buildSearchResults(AppLocalizations l10n) {
    if (_selection.isSearching) {
      return SkeletonShimmer(
        child: ListView.builder(
          itemCount: 8,
          itemBuilder: (_, _) => const SkeletonListTile(),
        ),
      );
    }
    if (_selection.searchResults.isEmpty) {
      return Center(
        child: Text(
          l10n.artistSelectorNoResults,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return _artistList(_selection.searchResults);
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
    if (_selection.selected.length >= _maxArtists) return;

    _suggestionsListKey.currentState?.removeItem(
      index,
      (context, animation) => _buildAnimatingChip(artist, animation),
      duration: const Duration(milliseconds: 180),
    );
    _selection.addSuggestion(index);
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
            data: Theme.of(context)
                .copyWith(splashFactory: NoSplash.splashFactory),
            child: AnimatedList(
              key: _suggestionsListKey,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              initialItemCount: _selection.suggestions.length,
              itemBuilder: (_, i, animation) {
                final artist = _selection.suggestions[i];
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
      key: ValueKey(ArtistSelectorController.keyOf(artist)),
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
          ArtistAvatar(imageUrl: artist.imageUrl, size: 36, iconSize: 16),
        ],
      ),
      title: Text(artist.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            onPressed: () => _selection.toggle(artist),
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
        final isSelected = _selection.isSelected(artist);
        return ListTile(
          visualDensity: const VisualDensity(vertical: -2),
          minVerticalPadding: 2,
          leading: ArtistAvatar(imageUrl: artist.imageUrl, size: 40),
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
          onTap: () => _selection.toggle(artist),
        );
      },
    );
  }
}
