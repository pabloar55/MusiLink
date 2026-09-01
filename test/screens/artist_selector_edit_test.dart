import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/artist_selector_screen.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/services/music_profile_service.dart';

import '../helpers/mocks.dart';

class _MockMusicCatalogService extends Mock implements MusicCatalogService {}

class _MockMusicProfileService extends Mock implements MusicProfileService {}

const _serverArtists = [
  Artist(name: 'Server artist 1', imageUrl: '', genres: []),
  Artist(name: 'Server artist 2', imageUrl: '', genres: []),
  Artist(name: 'Server artist 3', imageUrl: '', genres: []),
  Artist(name: 'Server artist 4', imageUrl: '', genres: []),
];

void main() {
  setUpAll(() => registerFallbackValue(<Artist>[]));

  testWidgets(
    'editar espera al guardado, muestra el error y permite reintentar',
    (tester) async {
      final auth = MockFirebaseAuth();
      final authUser = MockUser();
      final userService = MockUserService();
      final catalogService = _MockMusicCatalogService();
      final profileService = _MockMusicProfileService();
      const cachedUser = AppUser(
        uid: 'alice',
        displayName: 'Alice',
        topArtists: [
          Artist(name: 'Stale cached artist', imageUrl: '', genres: []),
        ],
      );
      const serverUser = AppUser(
        uid: 'alice',
        displayName: 'Alice',
        topArtists: _serverArtists,
      );
      const addedArtist = Artist(
        name: 'New artist',
        imageUrl: 'https://i.scdn.co/image/newartist',
        genres: ['rock'],
        spotifyId: '1234567890123456789012',
      );

      when(() => auth.currentUser).thenReturn(authUser);
      when(() => authUser.uid).thenReturn('alice');
      when(
        () => userService.getUser(
          'alice',
          bypassCache: true,
          serverOnly: true,
          reportErrors: false,
        ),
      ).thenAnswer((_) async => serverUser);
      when(() => catalogService.getRelatedArtists(any()))
          .thenAnswer((_) async => const []);
      when(() => catalogService.searchArtists('new', limit: 10))
          .thenAnswer((_) async => const [addedArtist]);
      when(
        () => profileService.saveManualArtists(any()),
      ).thenThrow(FirebaseException(plugin: 'functions', code: 'unavailable'));

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Profile')),
          ),
          GoRoute(
            path: '/artists',
            builder: (_, _) => const ArtistSelectorScreen(isEditMode: true),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            userServiceProvider.overrideWithValue(userService),
            musicCatalogServiceProvider.overrideWithValue(catalogService),
            musicProfileServiceProvider.overrideWithValue(profileService),
            currentUserProvider.overrideWith((_) => Stream.value(cachedUser)),
          ],
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      unawaited(router.push('/artists'));
      await tester.pumpAndSettle();

      expect(find.text('Server artist 1'), findsOneWidget);
      expect(find.text('Stale cached artist'), findsNothing);

      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text(addedArtist.name));
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(ArtistSelectorScreen), findsOneWidget);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      verify(() => profileService.saveManualArtists(any())).called(1);

      when(() => profileService.saveManualArtists(any()))
          .thenAnswer((_) async {});
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      verify(() => profileService.saveManualArtists(any())).called(1);
    },
  );
}
