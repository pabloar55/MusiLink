import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/artist_release.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/music_profile_sync_provider.dart';
import 'package:musi_link/providers/session_scope_provider.dart';
import 'package:musi_link/services/artist_release_service.dart';

final artistReleaseServiceProvider = Provider<ArtistReleaseService>((ref) {
  return ArtistReleaseService(firestore: ref.watch(firebaseFirestoreProvider));
});

/// Artistas del perfil que determinan las novedades. Solo cambia cuando cambia
/// la selección, no con cada actualización del documento del usuario.
final _releaseArtistsProvider = Provider<_ReleaseArtists>((ref) {
  return ref.watch(
    effectiveCurrentUserProvider.select(
      (user) => _ReleaseArtists(user.asData?.value?.topArtists ?? const []),
    ),
  );
});

/// Novedades de la semana de los artistas seguidos («Mi Top» › «Novedades»).
final weeklyReleasesProvider = FutureProvider<List<ArtistRelease>>((ref) {
  ref.watch(sessionUidProvider);
  final artists = ref.watch(_releaseArtistsProvider).artists;
  return ref.watch(artistReleaseServiceProvider).fetchWeeklyReleases(artists);
});

@immutable
class _ReleaseArtists {
  const _ReleaseArtists(this.artists);

  final List<Artist> artists;

  List<String?> get _keys => [
    for (final artist in artists) '${artist.spotifyId}:${artist.name}',
  ];

  @override
  bool operator ==(Object other) =>
      other is _ReleaseArtists && listEquals(other._keys, _keys);

  @override
  int get hashCode => Object.hashAll(_keys);
}
