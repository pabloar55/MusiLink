import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/music_profile_sync_coordinator.dart';
import 'package:musi_link/services/pending_music_profile_store.dart';
import 'package:musi_link/utils/artist_identity.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

class PendingMusicProfilesNotifier extends Notifier<Map<String, List<Artist>>> {
  @override
  Map<String, List<Artist>> build() => const {};

  void setArtists(String uid, List<Artist> artists) {
    state = {...state, uid: List<Artist>.unmodifiable(artists)};
  }

  void clear(String uid) {
    if (!state.containsKey(uid)) return;
    state = Map<String, List<Artist>>.from(state)..remove(uid);
  }
}

final pendingMusicProfilesProvider =
    NotifierProvider<PendingMusicProfilesNotifier, Map<String, List<Artist>>>(
      PendingMusicProfilesNotifier.new,
    );

final effectiveCurrentUserProvider = Provider<AsyncValue<AppUser?>>((ref) {
  final pendingProfiles = ref.watch(pendingMusicProfilesProvider);
  return ref.watch(currentUserProvider).whenData((user) {
    if (user == null) return null;
    final pendingArtists = pendingProfiles[user.uid];
    if (pendingArtists == null) return user;
    final pendingGenres = ref
        .read(musicCatalogServiceProvider)
        .getTopGenresFromArtists(pendingArtists, MusicProfileLimits.maxGenres);
    return user.copyWith(
      topArtists: pendingArtists,
      topGenres: pendingGenres,
      topArtistNames: pendingArtists
          .map((artist) => artist.name)
          .toList(growable: false),
      topArtistKeys: artistIdentityKeys(pendingArtists),
      topGenreNames: pendingGenres
          .map((genre) => genre.name)
          .toList(growable: false),
    );
  });
});

final musicProfileSyncCoordinatorProvider =
    Provider<MusicProfileSyncCoordinator>((ref) {
      final coordinator = MusicProfileSyncCoordinator(
        store: PendingMusicProfileStore(ref.watch(sharedPreferencesProvider)),
        profileService: ref.watch(musicProfileServiceProvider),
        currentUid: () => ref.read(firebaseAuthProvider).currentUser?.uid,
        onPending: (uid, artists) {
          ref
              .read(pendingMusicProfilesProvider.notifier)
              .setArtists(uid, artists);
        },
        onSaved: (uid) {
          ref.read(pendingMusicProfilesProvider.notifier).clear(uid);
          ref.read(userServiceProvider).clearCache();
          ref.invalidate(currentUserProvider);
        },
      );
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });
