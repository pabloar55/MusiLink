// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/router/app_router.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late StreamController<User?> authStream;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    when(() => mockUser.uid).thenReturn('uid123');
    authStream = StreamController<User?>.broadcast();
    when(() => mockAuth.authStateChanges())
        .thenAnswer((_) => authStream.stream);
  });

  tearDown(() => authStream.close());

  AppRouterNotifier buildNotifier() => AppRouterNotifier(auth: mockAuth);

  // ── Estado 1: app no inicializada ──────────────────────────────

  group('not initialized', () {
    test('sin usuario → /auth', () {
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = buildNotifier();
      expect(appRedirect(n, '/'), '/auth');
      expect(appRedirect(n, '/auth'), isNull);
      n.dispose();
    });

    test('con usuario → sin redirect hasta que llegue el bootstrap', () {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      final n = buildNotifier();
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });
  });

  // ── Estado 2: inicializado, no autenticado ─────────────────────

  group('not logged in', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(null));

    test('cualquier ruta → /auth', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/'), '/auth');
      n.dispose();
    });

    test('ya en /auth → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/auth'), isNull);
      n.dispose();
    });
  });

  group('account deletion pending', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('cualquier ruta queda bloqueada en progreso de eliminación', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: true,
        );
      expect(appRedirect(n, '/'), '/deleting-account');
      expect(appRedirect(n, '/deleting-account'), isNull);
      n.dispose();
    });

    test('conserva el bloqueo si no puede refrescar su estado', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      final n = AppRouterNotifier(
        auth: mockAuth,
        initialState: const AppRouterBootstrapState(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: true,
          setupStateKnown: true,
          userUid: 'uid123',
        ),
        fetchUserState: (_) async => (
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: null,
        ),
      );

      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);

      expect(n.deletionPending, isTrue);
      expect(appRedirect(n, '/'), '/deleting-account');
      n.dispose();
    });
  });

  // ── Estado 3: autenticado, sin onboarding ─────────────────────
  // Nuevo flujo: onboarding es el primer paso tras login

  group('logged in, no onboarding', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('cualquier ruta → /onboarding', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/'), '/onboarding');
      expect(appRedirect(n, '/auth'), '/onboarding');
      n.dispose();
    });

    test('ya en /onboarding → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/onboarding'), isNull);
      n.dispose();
    });
  });

  group('logged in, setup state unknown', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('un fallo de red no redirige al flujo de alta', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
          setupStateKnown: false,
        );

      expect(appRedirect(n, '/'), isNull);
      expect(appRedirect(n, '/onboarding'), '/');
      expect(appRedirect(n, '/username-setup'), '/');
      n.dispose();
    });

    test('conserva el snapshot válido si el refresco falla', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      final n = AppRouterNotifier(
        auth: mockAuth,
        initialState: const AppRouterBootstrapState(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: false,
          setupStateKnown: true,
          userUid: 'uid123',
        ),
        fetchUserState: (_) => Future.error(Exception('offline')),
      );

      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);

      expect(n.setupStateKnown, isTrue);
      expect(n.usernameSet, isTrue);
      expect(n.artistsSelected, isTrue);
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });

    test('restaura la caché del UID si el refresco tras login falla', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = AppRouterNotifier(
        auth: mockAuth,
        initialState: const AppRouterBootstrapState(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
          deletionPending: false,
          setupStateKnown: true,
        ),
        readCachedUserState: (_) => (
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: null,
        ),
        fetchUserState: (_) => Future.error(TimeoutException('offline')),
      );

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);

      expect(n.setupStateKnown, isTrue);
      expect(n.usernameSet, isTrue);
      expect(n.artistsSelected, isTrue);
      expect(appRedirect(n, '/auth'), '/');
      n.dispose();
    });

    test('sin caché un timeout mantiene el setup desconocido', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = AppRouterNotifier(
        auth: mockAuth,
        initialState: const AppRouterBootstrapState(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
          deletionPending: false,
          setupStateKnown: true,
        ),
        readCachedUserState: (_) => null,
        fetchUserState: (_) => Future.error(TimeoutException('offline')),
      );

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);

      expect(n.setupStateKnown, isFalse);
      expect(appRedirect(n, '/auth'), isNull);
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });

    test(
      'el alta espera en auth y no muestra discovery antes del onboarding',
      () {
        final n = buildNotifier()
          ..setInitialized(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
            setupStateKnown: false,
          );

        expect(appRedirect(n, '/auth'), isNull);

        n.setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
        );
        expect(appRedirect(n, '/auth'), '/onboarding');
        n.dispose();
      },
    );
  });

  // ── Estado 4: onboarding completado, sin username ─────────────

  group('logged in + onboarding done, no username', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('cualquier ruta → /username-setup', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/'), '/username-setup');
      expect(appRedirect(n, '/auth'), '/username-setup');
      n.dispose();
    });

    test('ya en /username-setup → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/username-setup'), isNull);
      n.dispose();
    });
  });

  // ── Estado 5: onboarding + username, sin foto ─────────────────

  group('logged in + onboarding + username, no photo setup', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('cualquier ruta → /photo-setup', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/'), '/photo-setup');
      n.dispose();
    });

    test('ya en /photo-setup → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: false,
        );
      expect(appRedirect(n, '/photo-setup'), isNull);
      n.dispose();
    });
  });

  // ── Estado 6: onboarding + username + foto, sin artistas ──────

  group('logged in + onboarding + username + photo, no artists', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('cualquier ruta → /artist-select', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: true,
        );
      expect(appRedirect(n, '/'), '/artist-select');
      n.dispose();
    });

    test('ya en /artist-select → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: true,
        );
      expect(appRedirect(n, '/artist-select'), isNull);
      n.dispose();
    });
  });

  // ── Estado 7: usuario completo ────────────────────────────────

  group('fully ready', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('pantallas de setup → /', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
        );
      expect(appRedirect(n, '/auth'), '/');
      expect(appRedirect(n, '/onboarding'), '/');
      expect(appRedirect(n, '/username-setup'), '/');
      expect(appRedirect(n, '/photo-setup'), '/');
      expect(appRedirect(n, '/artist-select'), '/');
      n.dispose();
    });

    test('pantallas normales → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
        );
      expect(appRedirect(n, '/'), isNull);
      expect(appRedirect(n, '/settings'), isNull);
      expect(appRedirect(n, '/search'), isNull);
      expect(appRedirect(n, '/chat'), isNull);
      n.dispose();
    });
  });

  // ── Transiciones de estado ─────────────────────────────────────

  group('state transitions', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    test('setOnboardingDone avanza a /username-setup', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
        )
        ..setOnboardingDone();
      expect(appRedirect(n, '/'), '/username-setup');
      n.dispose();
    });

    test('setUsernameSet avanza a /photo-setup', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: false,
        )
        ..setUsernameSet();
      expect(appRedirect(n, '/'), '/photo-setup');
      n.dispose();
    });

    test('setPhotoSetupDone avanza a /artist-select', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: false,
        )
        ..setPhotoSetupDone();
      expect(appRedirect(n, '/photo-setup'), '/artist-select');
      expect(appRedirect(n, '/artist-select'), isNull);
      n.dispose();
    });

    test('setArtistsSelected desbloquea la app', () {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: true,
        )
        ..setArtistsSelected();
      expect(appRedirect(n, '/artist-select'), '/');
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });

    test('sign-out resetea todos los flags de setup', () async {
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
        );

      expect(n.usernameSet, isTrue);
      expect(n.artistsSelected, isTrue);
      expect(n.onboardingDone, isTrue);
      expect(n.photoSetupDone, isTrue);

      authStream.add(null);
      await Future.microtask(() {});

      expect(n.usernameSet, isFalse);
      expect(n.artistsSelected, isFalse);
      expect(n.onboardingDone, isFalse);
      expect(n.photoSetupDone, isFalse);

      when(() => mockAuth.currentUser).thenReturn(null);
      expect(appRedirect(n, '/'), '/auth');
      n.dispose();
    });
  });
  test(
    'un refresco antiguo no deshace onboarding ni completa la foto',
    () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      final response = Completer<UserSetupState>();
      final saved = <UserSetupState>[];
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
          setupStateUid: 'uid123',
          fetchUserState: (_) => response.future,
          persistUserState: (uid, state) async {
            saved.add(state);
          },
        );
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      n.setOnboardingDone();
      response.complete((
        usernameSet: true,
        artistsSelected: false,
        onboardingDone: false,
        photoSetupDone: false,
        deletionPending: false,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(n.onboardingDone, isTrue);
      expect(n.photoSetupDone, isFalse);
      expect(appRedirect(n, '/'), '/photo-setup');
      expect(saved.last.onboardingDone, isTrue);
      expect(saved.last.photoSetupDone, isFalse);
      n.dispose();
    },
  );

  test(
    'cambiar de cuenta descarta el refresco y progreso de la anterior',
    () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      final oldResponse = Completer<UserSetupState>();
      final other = MockUser();
      when(() => other.uid).thenReturn('other');
      final n = buildNotifier()
        ..setInitialized(
          usernameSet: true,
          artistsSelected: false,
          onboardingDone: true,
          photoSetupDone: true,
          setupStateUid: 'uid123',
          fetchUserState: (uid) => uid == 'uid123'
              ? oldResponse.future
              : Future.value((
                  usernameSet: false,
                  artistsSelected: false,
                  onboardingDone: false,
                  photoSetupDone: false,
                  deletionPending: false,
                )),
        );
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      when(() => mockAuth.currentUser).thenReturn(other);
      authStream.add(other);
      await Future<void>.delayed(Duration.zero);
      oldResponse.complete((
        usernameSet: true,
        artistsSelected: true,
        onboardingDone: true,
        photoSetupDone: true,
        deletionPending: false,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(n.onboardingDone, isFalse);
      expect(n.photoSetupDone, isFalse);
      expect(n.usernameSet, isFalse);
      expect(appRedirect(n, '/'), '/onboarding');
      n.dispose();
    },
  );
}
