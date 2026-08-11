import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/service_providers.dart';

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
  @override
  DailySongSaveState build() => const DailySongSaveState.idle();

  Future<bool> save(String uid, Track track) async {
    if (state.isSaving) return false;
    state = DailySongSaveState.saving(track);
    try {
      await ref.read(userServiceProvider).setDailySong(uid, track);
      state = const DailySongSaveState.idle();
      return true;
    } catch (error) {
      state = DailySongSaveState.error(track, error);
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
