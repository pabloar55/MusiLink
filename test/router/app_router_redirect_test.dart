// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/services/terms_acceptance_controller.dart';
import 'package:musi_link/services/user_setup_controller.dart';

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

  AppRouterNotifier buildNotifier({
    bool termsRequired = false,
    UserSetupBootstrapState? initialState,
    FetchUserSetupState? fetchUserState,
    ReadCachedUserSetupState? readCachedUserState,
    PersistUserSetupState? persistUserState,
    bool Function(String uid)? readCachedTermsAcceptance,
    Future<bool> Function(String uid)? refreshTermsAcceptance,
    Future<bool> Function(String uid)? submitTermsAcceptance,
  }) {
    final setup = UserSetupController(
      auth: mockAuth,
      fetchUserState: fetchUserState,
      readCachedUserState: readCachedUserState,
      persistUserState: persistUserState,
    );
    final terms = TermsAcceptanceController(
      auth: mockAuth,
      acceptanceRequired: termsRequired,
      readCachedAcceptance: readCachedTermsAcceptance,
      refreshAcceptance: refreshTermsAcceptance,
      submitAcceptance: submitTermsAcceptance,
    );
    addTearDown(setup.dispose);
    addTearDown(terms.dispose);
    return AppRouterNotifier(
      auth: mockAuth,
      setup: setup,
      terms: terms,
      initialState: initialState,
    );
  }

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
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
        );
      expect(appRedirect(n, '/'), '/auth');
      n.dispose();
    });

    test('ya en /auth → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
            deletionPending: true,
          ),
        );
      expect(appRedirect(n, '/'), '/deleting-account');
      expect(appRedirect(n, '/deleting-account'), isNull);
      n.dispose();
    });

    test('conserva el bloqueo si no puede refrescar su estado', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      final n = buildNotifier(
        initialState: const UserSetupBootstrapState(
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

      expect(n.setup.deletionPending, isTrue);
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
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
        );
      expect(appRedirect(n, '/'), '/onboarding');
      expect(appRedirect(n, '/auth'), '/onboarding');
      n.dispose();
    });

    test('ya en /onboarding → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
            setupStateKnown: false,
          ),
        );

      expect(appRedirect(n, '/'), isNull);
      expect(appRedirect(n, '/onboarding'), '/');
      expect(appRedirect(n, '/username-setup'), '/');
      n.dispose();
    });

    test('conserva el snapshot válido si el refresco falla', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      final n = buildNotifier(
        initialState: const UserSetupBootstrapState(
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

      expect(n.setup.setupStateKnown, isTrue);
      expect(n.setup.usernameSet, isTrue);
      expect(n.setup.artistsSelected, isTrue);
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });

    test('restaura la caché del UID si el refresco tras login falla', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = buildNotifier(
        initialState: const UserSetupBootstrapState(
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

      expect(n.setup.setupStateKnown, isTrue);
      expect(n.setup.usernameSet, isTrue);
      expect(n.setup.artistsSelected, isTrue);
      expect(appRedirect(n, '/auth'), '/');
      n.dispose();
    });

    test('sin caché un timeout mantiene el setup desconocido', () async {
      when(() => mockUser.uid).thenReturn('uid123');
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = buildNotifier(
        initialState: const UserSetupBootstrapState(
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

      expect(n.setup.setupStateKnown, isFalse);
      expect(appRedirect(n, '/auth'), isNull);
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });

    test(
      'el alta espera en auth y no muestra discovery antes del onboarding',
      () {
        final n = buildNotifier()
          ..setInitialized(
            const UserSetupBootstrapState(
              usernameSet: false,
              artistsSelected: false,
              onboardingDone: false,
              photoSetupDone: false,
              setupStateKnown: false,
            ),
          );

        expect(appRedirect(n, '/auth'), isNull);

        n.setInitialized(
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: false,
          ),
        );
      expect(appRedirect(n, '/'), '/username-setup');
      expect(appRedirect(n, '/auth'), '/username-setup');
      n.dispose();
    });

    test('ya en /username-setup → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: false,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: false,
          ),
        );
      expect(appRedirect(n, '/'), '/photo-setup');
      n.dispose();
    });

    test('ya en /photo-setup → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: false,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: true,
          ),
        );
      expect(appRedirect(n, '/'), '/artist-select');
      n.dispose();
    });

    test('ya en /artist-select → sin redirect', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: true,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
          ),
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
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
        )
        ..setup.setOnboardingDone();
      expect(appRedirect(n, '/'), '/username-setup');
      n.dispose();
    });

    test('setUsernameSet avanza a /photo-setup', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: false,
          ),
        )
        ..setup.setUsernameSet();
      expect(appRedirect(n, '/'), '/photo-setup');
      n.dispose();
    });

    test('setPhotoSetupDone avanza a /artist-select', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: false,
          ),
        )
        ..setup.setPhotoSetupDone();
      expect(appRedirect(n, '/photo-setup'), '/artist-select');
      expect(appRedirect(n, '/artist-select'), isNull);
      n.dispose();
    });

    test('setArtistsSelected desbloquea la app', () {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: false,
            onboardingDone: true,
            photoSetupDone: true,
          ),
        )
        ..setup.setArtistsSelected();
      expect(appRedirect(n, '/artist-select'), '/');
      expect(appRedirect(n, '/'), isNull);
      n.dispose();
    });

    test('sign-out resetea todos los flags de setup', () async {
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
          ),
        );

      expect(n.setup.usernameSet, isTrue);
      expect(n.setup.artistsSelected, isTrue);
      expect(n.setup.onboardingDone, isTrue);
      expect(n.setup.photoSetupDone, isTrue);

      authStream.add(null);
      await Future.microtask(() {});

      expect(n.setup.usernameSet, isFalse);
      expect(n.setup.artistsSelected, isFalse);
      expect(n.setup.onboardingDone, isFalse);
      expect(n.setup.photoSetupDone, isFalse);

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
      final n =
          buildNotifier(
            fetchUserState: (_) => response.future,
            persistUserState: (uid, state) async {
              saved.add(state);
            },
          )..setInitialized(
            const UserSetupBootstrapState(
              usernameSet: true,
              artistsSelected: false,
              onboardingDone: false,
              photoSetupDone: false,
              userUid: 'uid123',
            ),
          );
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      n.setup.setOnboardingDone();
      response.complete((
        usernameSet: true,
        artistsSelected: false,
        onboardingDone: false,
        photoSetupDone: false,
        deletionPending: false,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(n.setup.onboardingDone, isTrue);
      expect(n.setup.photoSetupDone, isFalse);
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
      final n =
          buildNotifier(
            fetchUserState: (uid) => uid == 'uid123'
                ? oldResponse.future
                : Future.value((
                    usernameSet: false,
                    artistsSelected: false,
                    onboardingDone: false,
                    photoSetupDone: false,
                    deletionPending: false,
                  )),
          )..setInitialized(
            const UserSetupBootstrapState(
              usernameSet: true,
              artistsSelected: false,
              onboardingDone: true,
              photoSetupDone: true,
              userUid: 'uid123',
            ),
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
      expect(n.setup.onboardingDone, isFalse);
      expect(n.setup.photoSetupDone, isFalse);
      expect(n.setup.usernameSet, isFalse);
      expect(appRedirect(n, '/'), '/onboarding');
      n.dispose();
    },
  );

  test(
    'un cambio de sesión actualiza términos y alta antes de avisar',
    () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      final other = MockUser();
      when(() => other.uid).thenReturn('other');
      final n = buildNotifier(
        termsRequired: true,
        readCachedTermsAcceptance: (_) => true,
        fetchUserState: (_) => Completer<UserSetupState>().future,
        readCachedUserState: (uid) => uid == 'other'
            ? (
                usernameSet: false,
                artistsSelected: false,
                onboardingDone: false,
                photoSetupDone: false,
                deletionPending: null,
              )
            : null,
        initialState: const UserSetupBootstrapState(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          userUid: 'uid123',
        ),
      );
      addTearDown(n.dispose);
      final redirects = <String?>[];
      n.addListener(() => redirects.add(appRedirect(n, '/')));

      when(() => mockAuth.currentUser).thenReturn(other);
      authStream.add(other);
      await Future<void>.delayed(Duration.zero);

      expect(redirects, ['/onboarding']);
    },
  );

  group('terms acceptance', () {
    setUp(() => when(() => mockAuth.currentUser).thenReturn(mockUser));

    AppRouterNotifier cachedNotifier(
      Future<bool> Function(String) refresh, {
      bool cached = true,
      Future<bool> Function(String)? submit,
    }) => buildNotifier(
      termsRequired: true,
      readCachedTermsAcceptance: (uid) => cached && uid == 'uid123',
      refreshTermsAcceptance: refresh,
      submitTermsAcceptance: submit,
      initialState: const UserSetupBootstrapState(
        usernameSet: true,
        artistsSelected: true,
        onboardingDone: true,
        photoSetupDone: true,
        deletionPending: false,
        setupStateKnown: true,
        userUid: 'uid123',
      ),
    );

    test(
      'entra directamente al chat mientras verifica en segundo plano',
      () async {
        final pending = Completer<bool>();
        final checkedUids = <String>[];
        final notifier = cachedNotifier((uid) {
          checkedUids.add(uid);
          return pending.future;
        });
        addTearDown(notifier.dispose);
        expect(appRedirect(notifier, '/chat'), isNull);
        authStream.add(mockUser);
        await Future<void>.delayed(Duration.zero);
        expect(checkedUids, ['uid123']);
        expect(appRedirect(notifier, '/chat'), isNull);
        pending.complete(true);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.terms.termsAccepted, isTrue);
      },
    );

    test('conserva acceso con caché cuando falla la verificación', () async {
      final notifier = cachedNotifier((_) async => throw StateError('offline'));
      addTearDown(notifier.dispose);
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      expect(appRedirect(notifier, '/'), isNull);
      expect(notifier.terms.termsAccepted, isTrue);
    });

    testWidgets('sin caché reintenta la consulta fallida sin bloquear', (
      tester,
    ) async {
      var checks = 0;
      final notifier = cachedNotifier((_) async {
        checks++;
        if (checks == 1) throw StateError('offline');
        return false;
      }, cached: false);
      addTearDown(notifier.dispose);
      expect(appRedirect(notifier, '/chat'), isNull);
      expect(appRedirect(notifier, '/terms'), '/');
      authStream.add(mockUser);
      await tester.pump();
      expect(checks, 1);
      expect(notifier.terms.termsAccepted, isFalse);
      expect(notifier.terms.termsCheckPending, isTrue);
      expect(appRedirect(notifier, '/'), isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(checks, 2);
      expect(notifier.terms.termsCheckPending, isFalse);
      expect(appRedirect(notifier, '/'), '/terms');
    });

    testWidgets('cerrar sesión cancela los reintentos de términos', (
      tester,
    ) async {
      var checks = 0;
      final notifier = cachedNotifier((_) async {
        checks++;
        throw StateError('offline');
      }, cached: false);
      addTearDown(notifier.dispose);
      authStream.add(mockUser);
      await tester.pump();
      expect(checks, 1);
      when(() => mockAuth.currentUser).thenReturn(null);
      authStream.add(null);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(checks, 1);
      expect(appRedirect(notifier, '/'), '/auth');
    });

    test(
      'pide términos si el servidor invalida la aceptación guardada',
      () async {
        final notifier = cachedNotifier((_) async => false);
        addTearDown(notifier.dispose);
        expect(appRedirect(notifier, '/'), isNull);
        authStream.add(mockUser);
        await Future<void>.delayed(Duration.zero);
        expect(appRedirect(notifier, '/'), '/terms');
        expect(notifier.terms.termsAccepted, isFalse);
      },
    );

    test(
      'ignora la verificación de otra cuenta y restaura su propia caché',
      () async {
        final pending = Completer<bool>();
        final otherPending = Completer<bool>();
        final notifier = cachedNotifier(
          (uid) => uid == 'uid123' ? pending.future : otherPending.future,
        );
        addTearDown(notifier.dispose);
        authStream.add(mockUser);
        await Future<void>.delayed(Duration.zero);
        final other = MockUser();
        when(() => other.uid).thenReturn('other');
        when(() => mockAuth.currentUser).thenReturn(other);
        authStream.add(other);
        await Future<void>.delayed(Duration.zero);
        expect(appRedirect(notifier, '/'), isNull);
        pending.complete(true);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.terms.termsAccepted, isFalse);
        expect(notifier.terms.termsCheckPending, isTrue);
        otherPending.complete(false);
        await Future<void>.delayed(Duration.zero);
        expect(appRedirect(notifier, '/'), '/terms');

        when(() => mockAuth.currentUser).thenReturn(mockUser);
        authStream.add(mockUser);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.terms.termsAccepted, isTrue);
      },
    );

    test('un refresco anterior no deshace una nueva aceptación', () async {
      final pending = Completer<bool>();
      final notifier = cachedNotifier((_) => pending.future);
      addTearDown(notifier.dispose);
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      notifier.terms.setTermsAccepted('uid123');
      pending.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.terms.termsAccepted, isTrue);
    });

    testWidgets(
      'aceptar avanza al instante y reintenta el registro en segundo plano',
      (tester) async {
        var submissions = 0;
        final notifier = cachedNotifier(
          (_) async => false,
          cached: false,
          submit: (_) async {
            submissions++;
            if (submissions == 1) throw StateError('offline');
            return true;
          },
        );
        addTearDown(notifier.dispose);
        authStream.add(mockUser);
        await tester.pump();
        expect(appRedirect(notifier, '/'), '/terms');

        notifier.terms.acceptTerms('uid123');
        expect(appRedirect(notifier, '/terms'), '/');
        notifier.terms.acceptTerms('uid123');
        await tester.pump();
        expect(submissions, 1);

        // El servidor todavía no refleja la aceptación pendiente.
        authStream.add(mockUser);
        await tester.pump();
        expect(notifier.terms.termsAccepted, isTrue);

        await tester.pump(const Duration(seconds: 2));
        expect(submissions, 2);
        expect(notifier.terms.termsAccepted, isTrue);
        expect(notifier.terms.takeTermsSaveError(), isFalse);
      },
    );

    test('un rechazo del registro vuelve a exigir la aceptación', () async {
      final notifier = cachedNotifier(
        (_) async => false,
        cached: false,
        submit: (_) async => false,
      );
      addTearDown(notifier.dispose);
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);

      notifier.terms.acceptTerms('uid123');
      expect(appRedirect(notifier, '/terms'), '/');
      await Future<void>.delayed(Duration.zero);
      expect(appRedirect(notifier, '/'), '/terms');
      expect(notifier.terms.takeTermsSaveError(), isTrue);
      expect(notifier.terms.takeTermsSaveError(), isFalse);
    });

    testWidgets('cerrar sesión cancela el registro pendiente', (tester) async {
      var submissions = 0;
      final notifier = cachedNotifier(
        (_) async => false,
        cached: false,
        submit: (_) async {
          submissions++;
          throw StateError('offline');
        },
      );
      addTearDown(notifier.dispose);
      authStream.add(mockUser);
      await tester.pump();
      notifier.terms.acceptTerms('uid123');
      await tester.pump();
      expect(submissions, 1);

      when(() => mockAuth.currentUser).thenReturn(null);
      authStream.add(null);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(submissions, 1);
      expect(notifier.terms.takeTermsSaveError(), isFalse);
    });

    test(
      'descarta la verificación tras cerrar sesión o destruir el router',
      () async {
        final pending = Completer<bool>();
        final notifier = cachedNotifier((_) => pending.future);
        authStream.add(mockUser);
        await Future<void>.delayed(Duration.zero);
        when(() => mockAuth.currentUser).thenReturn(null);
        authStream.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(appRedirect(notifier, '/'), '/auth');
        expect(notifier.terms.termsAccepted, isFalse);
        notifier.dispose();
        pending.complete(false);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test('bloquea cuentas nuevas y existentes hasta aceptar', () {
      final notifier = buildNotifier(
        termsRequired: true,
        initialState: const UserSetupBootstrapState(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: false,
          setupStateKnown: true,
          userUid: 'uid123',
        ),
      );

      expect(appRedirect(notifier, '/'), '/terms');
      expect(appRedirect(notifier, '/chat'), '/terms');
      expect(appRedirect(notifier, '/terms'), isNull);
      expect(appRedirect(notifier, '/privacy-policy'), isNull);
      notifier.terms.setTermsAccepted('otro');
      expect(appRedirect(notifier, '/'), '/terms');

      notifier.terms.setTermsAccepted('uid123');
      expect(appRedirect(notifier, '/terms'), '/');
      expect(appRedirect(notifier, '/chat'), isNull);
      notifier.dispose();
    });

    test('la cuenta nueva vuelve a onboarding tras aceptar', () {
      final notifier = buildNotifier(
        termsRequired: true,
        initialState: const UserSetupBootstrapState(
          usernameSet: false,
          artistsSelected: false,
          onboardingDone: false,
          photoSetupDone: false,
          deletionPending: false,
          setupStateKnown: true,
          userUid: 'uid123',
        ),
      );
      expect(appRedirect(notifier, '/onboarding'), '/terms');
      notifier.terms.setTermsAccepted('uid123');
      expect(appRedirect(notifier, '/terms'), '/onboarding');
      notifier.dispose();
    });

    test('cambiar de cuenta invalida la aceptación en memoria', () async {
      final notifier = buildNotifier(
        termsRequired: true,
        initialState: const UserSetupBootstrapState(
          usernameSet: true,
          artistsSelected: true,
          onboardingDone: true,
          photoSetupDone: true,
          deletionPending: false,
          setupStateKnown: true,
          userUid: 'uid123',
        ),
      );
      notifier.terms.setTermsAccepted('uid123');
      authStream.add(mockUser);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.terms.termsAccepted, isTrue);

      final other = MockUser();
      when(() => other.uid).thenReturn('other');
      when(() => mockAuth.currentUser).thenReturn(other);
      authStream.add(other);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.terms.termsAccepted, isFalse);
      expect(appRedirect(notifier, '/'), '/terms');
      notifier.dispose();
    });
  });

  // ── Enlaces de perfil abiertos antes de poder entrar ───────────

  group('enlace de perfil pendiente', () {
    test('se retoma tras iniciar sesión y solo una vez', () {
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
          ),
        );
      expect(appRedirect(n, '/u/pablo'), '/auth');
      expect(n.pendingProfileLink, '/u/pablo');

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      // El router puede evaluar el redirect más de una vez antes de navegar.
      expect(appRedirect(n, '/auth'), '/u/pablo');
      expect(appRedirect(n, '/auth'), '/u/pablo');
      expect(appRedirect(n, '/u/pablo'), isNull);
      expect(n.pendingProfileLink, isNull);
      expect(appRedirect(n, '/auth'), '/');
      n.dispose();
    });

    test('sobrevive a todos los pasos del alta', () {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: false,
            artistsSelected: false,
            onboardingDone: false,
            photoSetupDone: false,
          ),
        );
      expect(appRedirect(n, '/u/pablo'), '/onboarding');
      n.setup.setOnboardingDone();
      expect(appRedirect(n, '/onboarding'), '/username-setup');
      n.setup.setUsernameSet();
      expect(appRedirect(n, '/username-setup'), '/photo-setup');
      n.setup.setPhotoSetupDone();
      expect(appRedirect(n, '/photo-setup'), '/artist-select');
      n.setup.setArtistsSelected();
      expect(appRedirect(n, '/artist-select'), '/u/pablo');
      n.dispose();
    });

    test('un usuario listo abre el enlace sin dejarlo pendiente', () {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
          ),
        );
      expect(appRedirect(n, '/u/pablo'), isNull);
      expect(n.pendingProfileLink, isNull);
      n.dispose();
    });

    testWidgets('el router vuelve al perfil al iniciar sesión', (tester) async {
      when(() => mockAuth.currentUser).thenReturn(null);
      final n = buildNotifier()
        ..setInitialized(
          const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
          ),
        );
      addTearDown(n.dispose);
      final router = GoRouter(
        initialLocation: '/u/pablo',
        refreshListenable: n,
        redirect: (_, state) => appRedirect(n, state.matchedLocation),
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                path: 'u/:username',
                builder: (_, state) => Text(
                  'perfil ${state.pathParameters['username']}',
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/auth',
            builder: (_, _) =>
                const Text('auth', textDirection: TextDirection.ltr),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        WidgetsApp.router(color: const Color(0xFF000000), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('auth'), findsOneWidget);

      when(() => mockAuth.currentUser).thenReturn(mockUser);
      authStream.add(mockUser);
      await tester.pumpAndSettle();
      expect(find.text('perfil pablo'), findsOneWidget);
      expect(router.canPop(), isTrue);
    });
  });
}
