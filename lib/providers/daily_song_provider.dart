import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/session_scope_provider.dart';
import 'package:musi_link/services/daily_song_interaction_service.dart';

final dailySongInteractionServiceProvider =
    Provider<DailySongInteractionService>((ref) {
      return DailySongInteractionService(
        firestore: ref.watch(firebaseFirestoreProvider),
        auth: ref.watch(firebaseAuthProvider),
      );
    });

final dailySongLikesProvider = StreamProvider.autoDispose
    .family<Set<String>, DailySongPublication>((ref, publication) {
      ref.watch(sessionUidProvider);
      return ref
          .watch(dailySongInteractionServiceProvider)
          .watchLikes(publication);
    });

final dailySongMyLikeProvider = StreamProvider.autoDispose
    .family<bool, DailySongPublication>((ref, publication) {
      ref.watch(sessionUidProvider);
      return ref
          .watch(dailySongInteractionServiceProvider)
          .watchMyLike(publication);
    });

/// Perfiles de amigos actualizados en tiempo real para la pestaña de canciones.
final friendProfilesStreamProvider = StreamProvider<List<AppUser>>((ref) {
  return ref
      .watch(friendsStreamProvider)
      .when(
        data: (friendIds) =>
            ref.watch(userServiceProvider).watchUsersByIds(friendIds),
        error: Stream<List<AppUser>>.error,
        loading: Stream<List<AppUser>>.empty,
      );
});

enum DailySongSaveStatus { idle, saving, error }

class DailySongSaveState {
  const DailySongSaveState._({
    required this.status,
    this.pendingTrack,
    this.error,
  });

  const DailySongSaveState.idle() : this._(status: DailySongSaveStatus.idle);

  const DailySongSaveState.saving(Track track)
    : this._(status: DailySongSaveStatus.saving, pendingTrack: track);

  const DailySongSaveState.error(Track track, Object error)
    : this._(
        status: DailySongSaveStatus.error,
        pendingTrack: track,
        error: error,
      );

  final DailySongSaveStatus status;
  final Track? pendingTrack;
  final Object? error;

  bool get isSaving => status == DailySongSaveStatus.saving;
  bool get hasError => status == DailySongSaveStatus.error;
}

class DailySongSaveNotifier extends Notifier<DailySongSaveState> {
  Object _session = Object();

  @override
  DailySongSaveState build() {
    ref.watch(sessionScopeProvider);
    _session = Object();
    return const DailySongSaveState.idle();
  }

  Future<bool> save(String uid, Track track) async {
    if (state.isSaving) return false;
    // El notifier sobrevive al cambio de sesión: un guardado que termina
    // después no debe tocar el estado de la sesión nueva.
    final session = _session;
    state = DailySongSaveState.saving(track);
    try {
      await ref.read(userServiceProvider).setDailySong(uid, track);
      if (identical(session, _session)) {
        state = const DailySongSaveState.idle();
      }
      return true;
    } catch (error) {
      if (identical(session, _session)) {
        state = DailySongSaveState.error(track, error);
      }
      return false;
    }
  }

  Future<bool> retry(String uid) async {
    final track = state.pendingTrack;
    if (track == null || state.isSaving) return false;
    state = const DailySongSaveState.idle();
    return save(uid, track);
  }

  void clearError() {
    if (state.hasError) state = const DailySongSaveState.idle();
  }
}

final dailySongSaveProvider =
    NotifierProvider<DailySongSaveNotifier, DailySongSaveState>(
      DailySongSaveNotifier.new,
    );
