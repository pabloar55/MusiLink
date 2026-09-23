import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:musi_link/utils/error_reporter.dart';

class DiscoverState {
  const DiscoverState({
    this.results = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.isStale = false,
    this.error,
  });

  final List<DiscoveryResult> results;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;

  /// true mientras se muestran resultados de caché y se refresca en background.
  final bool isStale;

  final Object? error;

  bool get hasError => error != null;

  DiscoverState copyWith({
    List<DiscoveryResult>? results,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isStale,
    Object? error = _sentinel,
  }) {
    return DiscoverState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      isStale: isStale ?? this.isStale,
      error: identical(error, _sentinel) ? this.error : error,
    );
  }
}

const _sentinel = Object();

class DiscoverNotifier extends Notifier<DiscoverState> {
  final Set<String> _hiddenUserIds = {};
  int _visibilityRevision = 0;

  @override
  DiscoverState build() => const DiscoverState(isLoading: true);

  void hideBlockedUser(String uid) {
    _visibilityRevision++;
    _hiddenUserIds.add(uid);
    state = state.copyWith(
      results: _visibleResults(state.results),
      isLoading: false,
      isLoadingMore: false,
      hasMore: false,
      isStale: false,
    );
  }

  void unhideUser(String uid) {
    _visibilityRevision++;
    _hiddenUserIds.remove(uid);
    state = state.copyWith(
      isLoading: false,
      isLoadingMore: false,
      hasMore: false,
      isStale: false,
    );
  }

  List<DiscoveryResult> _visibleResults(List<DiscoveryResult> results) =>
      results
          .where((result) => !_hiddenUserIds.contains(result.user.uid))
          .toList(growable: false);

  Future<void> loadDiscovery({bool useLocalCache = true}) async {
    final service = ref.read(musicProfileServiceProvider);
    final previousState = state;
    final revision = _visibilityRevision;

    if (useLocalCache) {
      // Intentar caché local de Firestore primero (< 100 ms, sin red).
      final cached = await service.readDiscoveryUsersFromLocalCache();
      if (revision != _visibilityRevision) return;
      if (cached != null) {
        state = state.copyWith(
          results: _visibleResults(cached),
          isLoading: false,
          isStale: true,
          hasMore: service.hasMoreDiscoveryUsers,
          error: null,
        );
        // Refrescar desde el servidor en background sin bloquear la UI.
        unawaited(_refreshInBackground(service, revision));
        return;
      }
    }

    // Sin datos visibles, mostrar shimmer y esperar al servidor.
    // En pull-to-refresh conservamos los resultados actuales para que solo
    // se vea el indicador de refresco hasta recibir la nueva lista.
    final keepVisibleResults = !useLocalCache && state.results.isNotEmpty;
    state = state.copyWith(
      isLoading: !keepVisibleResults,
      isStale: keepVisibleResults,
      error: null,
      results: keepVisibleResults ? null : [],
    );

    try {
      final results = await service.readStoredDiscoveryUsers();
      if (revision != _visibilityRevision) return;
      state = state.copyWith(
        results: _visibleResults(results),
        isLoading: false,
        isStale: false,
        hasMore: service.hasMoreDiscoveryUsers,
      );
    } on BlockedUsersReadException {
      if (revision != _visibilityRevision) return;
      state = previousState.copyWith(
        results: _visibleResults(previousState.results),
        isLoading: false,
        isLoadingMore: false,
        isStale: false,
        error: null,
      );
    } catch (e, stack) {
      if (revision != _visibilityRevision) return;
      await reportError(e, stack);
      state = state.copyWith(isLoading: false, isStale: false, error: e);
    }
  }

  Future<void> refresh() => loadDiscovery(useLocalCache: false);

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isStale || !state.hasMore) return;
    final revision = _visibilityRevision;
    state = state.copyWith(isLoadingMore: true);

    try {
      final (allResults, hasMore) = await ref
          .read(musicProfileServiceProvider)
          .loadMoreDiscoveryUsers();
      if (revision != _visibilityRevision) return;

      state = state.copyWith(
        results: _visibleResults(allResults),
        isLoadingMore: false,
        hasMore: hasMore,
      );
    } catch (e, stack) {
      if (revision != _visibilityRevision) return;
      await reportError(e, stack);
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> _refreshInBackground(
    MusicProfileService service,
    int revision,
  ) async {
    try {
      final results = await service.readStoredDiscoveryUsers();
      if (revision != _visibilityRevision) return;
      state = state.copyWith(
        results: _visibleResults(results),
        isStale: false,
        hasMore: service.hasMoreDiscoveryUsers,
      );
    } catch (e, stack) {
      if (revision != _visibilityRevision) return;
      await reportError(e, stack);
      // Mantenemos los resultados de caché visibles; solo limpiamos isStale.
      state = state.copyWith(isStale: false);
    }
  }
}

final discoverProvider = NotifierProvider<DiscoverNotifier, DiscoverState>(
  DiscoverNotifier.new,
);
