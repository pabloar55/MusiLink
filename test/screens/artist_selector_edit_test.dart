import 'dart:async';

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
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/artist_selector_screen.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    'una consulta fallida de similares se reintenta al volver a seleccionar',
    (tester) async {
      final catalog = _MockMusicCatalogService();
      const muse = Artist(
        name: 'Muse',
        imageUrl: 'https://i.scdn.co/image/muse',
        genres: ['rock'],
      );
      const related = Artist(name: 'Radiohead', imageUrl: '', genres: []);
      var attempts = 0;
      final failure = MockFirebaseFunctionsException();
      when(() => failure.code).thenReturn('resource-exhausted');
      when(() => catalog.searchArtists('muse', limit: 10))
          .thenAnswer((_) async => [muse]);
      when(() => catalog.getRelatedArtists('Muse')).thenAnswer((_) async {
        if (attempts++ == 0) throw failure;
        return [related];
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [musicCatalogServiceProvider.overrideWithValue(catalog)],
          child: const MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ArtistSelectorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.enterText(find.byType(TextField), 'muse');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Muse'));
        await tester.pumpAndSettle();
        if (attempt == 0) {
          expect(find.text('Radiohead'), findsNothing);
          await tester.tap(find.widgetWithIcon(IconButton, Icons.close).last);
          await tester.pumpAndSettle();
        }
      }
      expect(find.text('Radiohead'), findsOneWidget);
      verify(() => catalog.getRelatedArtists('Muse')).called(2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in [const Locale('es'), const Locale('el')]) {
    testWidgets(
      'la cabecera no se mueve al mostrar y ocultar la flecha (${locale.languageCode})',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final catalog = _MockMusicCatalogService();
        when(() => catalog.searchArtists('artist', limit: 10))
            .thenAnswer((_) async => _serverArtists);
        when(() => catalog.searchArtists(any(), limit: 1))
            .thenAnswer((_) async => []);
        when(() => catalog.getRelatedArtists(any()))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [musicCatalogServiceProvider.overrideWithValue(catalog)],
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ArtistSelectorScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(ArtistSelectorScreen));
        final l10n = AppLocalizations.of(context)!;
        final title = find.text(l10n.artistSelectorTitle);
        final titleBounds = tester.getRect(title);
        final searchBounds = tester.getRect(find.byType(TextField));
        final arrow = find.widgetWithIcon(IconButton, Icons.arrow_forward);
        expect(arrow.hitTestable(), findsNothing);

        for (final artist in _serverArtists) {
          await tester.enterText(find.byType(TextField), 'artist');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          await tester.tap(find.text(artist.name));
          await tester.pumpAndSettle();
          expect(tester.getRect(title), titleBounds);
          expect(tester.getRect(find.byType(TextField)), searchBounds);
        }
        expect(arrow.hitTestable(), findsOneWidget);
        final arrowBounds = tester.getRect(find.byIcon(Icons.arrow_forward));
        expect(arrowBounds.center.dy, closeTo(titleBounds.center.dy, 1));
        expect(360 - arrowBounds.right, 24);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.close).last);
        await tester.pumpAndSettle();
        expect(arrow.hitTestable(), findsNothing);
        expect(tester.getRect(title), titleBounds);
        expect(tester.getRect(find.byType(TextField)), searchBounds);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editar sale sin esperar a Firebase y reabre con los cambios pendientes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
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
      final remoteSave = Completer<void>();

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
      when(() => profileService.saveManualArtists(any()))
          .thenAnswer((_) => remoteSave.future);

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
            sharedPreferencesProvider.overrideWithValue(preferences),
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

      expect(find.text('Profile'), findsOneWidget);
      verify(() => profileService.saveManualArtists(any())).called(1);

      unawaited(router.push('/artists'));
      await tester.pumpAndSettle();
      expect(find.text(addedArtist.name), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);

      remoteSave.complete();
      await tester.pump();
    },
  );
}
