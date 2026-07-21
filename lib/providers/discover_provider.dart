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
  @override
  DiscoverState build() => const DiscoverState(isLoading: true);

  Future<void> loadDiscovery({bool useLocalCache = true}) async {
    final service = ref.read(musicProfileServiceProvider);

    if (useLocalCache) {
      // Intentar caché local de Firestore primero (< 100 ms, sin red).
      final cached = await service.readDiscoveryUsersFromLocalCache();
      if (cached != null) {
        state = state.copyWith(
          results: cached,
          isLoading: false,
          isStale: true,
          hasMore: service.hasMoreDiscoveryUsers,
          error: null,
        );
        // Refrescar desde el servidor en background sin bloquear la UI.
        unawaited(_refreshInBackground(service));
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
      state = state.copyWith(
        results: results,
        isLoading: false,
        isStale: false,
        hasMore: service.hasMoreDiscoveryUsers,
      );
    } catch (e, stack) {
      await reportError(e, stack);
      state = state.copyWith(isLoading: false, isStale: false, error: e);
    }
  }

  Future<void> refresh() => loadDiscovery(useLocalCache: false);

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final (allResults, hasMore) = await ref
          .read(musicProfileServiceProvider)
          .loadMoreDiscoveryUsers();

      state = state.copyWith(
        results: allResults,
        isLoadingMore: false,
        hasMore: hasMore,
      );
    } catch (e, stack) {
      await reportError(e, stack);
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> _refreshInBackground(MusicProfileService service) async {
    try {
      final results = await service.readStoredDiscoveryUsers();
      state = state.copyWith(
        results: results,
        isStale: false,
        hasMore: service.hasMoreDiscoveryUsers,
      );
    } catch (e, stack) {
      await reportError(e, stack);
      // Mantenemos los resultados de caché visibles; solo limpiamos isStale.
      state = state.copyWith(isStale: false);
    }
  }
}

final discoverProvider = NotifierProvider<DiscoverNotifier, DiscoverState>(
  DiscoverNotifier.new,
);
