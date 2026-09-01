import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/genre.dart';
import 'package:musi_link/providers/music_profile_sync_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/music_catalog_service.dart';

class _MockMusicCatalogService extends Mock implements MusicCatalogService {}

void main() {
  setUpAll(() => registerFallbackValue(<Artist>[]));

  test(
    'superpone artistas y géneros pendientes sobre el perfil remoto',
    () async {
      final catalogService = _MockMusicCatalogService();
      when(() => catalogService.getTopGenresFromArtists(any(), 10))
          .thenReturn(const [Genre(name: 'rock', count: 1, percentage: 100)]);
      const remoteUser = AppUser(
        uid: 'alice',
        displayName: 'Alice',
        topArtists: [
          Artist(name: 'Old', imageUrl: '', genres: ['pop']),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          musicCatalogServiceProvider.overrideWithValue(catalogService),
          currentUserProvider.overrideWith((_) => Stream.value(remoteUser)),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        currentUserProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(currentUserProvider.future);

      container.read(pendingMusicProfilesProvider.notifier).setArtists(
        'alice',
        const [
          Artist(
            name: 'New',
            imageUrl: '',
            genres: ['Rock'],
            spotifyId: '1234567890123456789012',
          ),
        ],
      );

      final effective = container
          .read(effectiveCurrentUserProvider)
          .requireValue;
      expect(effective?.topArtistNames, ['New']);
      expect(effective?.topArtistKeys, ['spotify:1234567890123456789012']);
      expect(effective?.topGenreNames, ['rock']);
    },
  );
}
