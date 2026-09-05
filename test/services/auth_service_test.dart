import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/auth_service.dart';

import '../helpers/mocks.dart';

// Fallback para AuthCredential
class FakeAuthCredential extends Fake implements AuthCredential {}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockGoogleSignIn mockGoogleSignIn;
  late MockUserService mockUserService;
  late MockNotificationService mockNotificationService;
  late AuthService authService;

  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = null;
    mockAuth = MockFirebaseAuth();
    mockGoogleSignIn = MockGoogleSignIn();
    mockUserService = MockUserService();
    mockNotificationService = MockNotificationService();
    authService = AuthService(
      mockUserService,
      auth: mockAuth,
      googleSignIn: mockGoogleSignIn,
      notificationService: mockNotificationService,
    );
  });

  group('AuthService', () {
    group('currentUser', () {
      test('devuelve el usuario actual de FirebaseAuth', () {
        final mockUser = MockUser();
        when(() => mockAuth.currentUser).thenReturn(mockUser);

        expect(authService.currentUser, mockUser);
      });

      test('devuelve null si no hay sesión', () {
        when(() => mockAuth.currentUser).thenReturn(null);

        expect(authService.currentUser, isNull);
      });
    });

    group('registerWithEmail', () {
      test(
        'registra usuario y actualiza displayName en Firebase Auth',
        () async {
          final mockUser = MockUser();
          final mockCredential = MockUserCredential();

          when(() => mockUser.uid).thenReturn('uid123');
          when(
            () => mockUser.updateDisplayName(any()),
          ).thenAnswer((_) async {});
          when(() => mockCredential.user).thenReturn(mockUser);
          when(
            () => mockAuth.createUserWithEmailAndPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenAnswer((_) async => mockCredential);

          final result = await authService.registerWithEmail(
            email: 'test@test.com',
            password: 'password123',
            displayName: 'Test User',
          );

          expect(result, mockUser);
          verify(() => mockUser.updateDisplayName('Test User')).called(1);
          // El perfil Firestore lo crea UsernameSetupScreen, no aquí.
          verifyNever(
            () => mockUserService.createUserProfile(
              displayName: any(named: 'displayName'),
              username: any(named: 'username'),
            ),
          );
        },
      );

      test('devuelve null si credential.user es null', () async {
        final mockCredential = MockUserCredential();
        when(() => mockCredential.user).thenReturn(null);
        when(
          () => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => mockCredential);

        final result = await authService.registerWithEmail(
          email: 'test@test.com',
          password: 'pass',
          displayName: 'Test',
        );

        expect(result, isNull);
      });

      test('propaga FirebaseAuthException', () async {
        when(
          () => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer(
          (_) async => throw FirebaseAuthException(
            code: 'email-already-in-use',
            message: 'Email already in use',
          ),
        );

        await expectLater(
          authService.registerWithEmail(
            email: 'test@test.com',
            password: 'pass',
            displayName: 'Test',
          ),
          throwsA(isA<FirebaseAuthException>()),
        );
      });
    });

    group('signInWithEmail', () {
      test('inicia sesión y actualiza lastLogin', () async {
        final mockUser = MockUser();
        final mockCredential = MockUserCredential();

        when(() => mockUser.uid).thenReturn('uid123');
        when(() => mockCredential.user).thenReturn(mockUser);
        when(
          () => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => mockCredential);
        when(
          () => mockUserService.updateLastLogin(any()),
        ).thenAnswer((_) async {});

        final result = await authService.signInWithEmail(
          email: 'test@test.com',
          password: 'password123',
        );

        expect(result, mockUser);
        verify(() => mockUserService.updateLastLogin('uid123')).called(1);
      });

      test('no actualiza lastLogin si user es null', () async {
        final mockCredential = MockUserCredential();
        when(() => mockCredential.user).thenReturn(null);
        when(
          () => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => mockCredential);

        final result = await authService.signInWithEmail(
          email: 'test@test.com',
          password: 'pass',
        );

        expect(result, isNull);
        verifyNever(() => mockUserService.updateLastLogin(any()));
      });

      test(
        'propaga FirebaseAuthException con credenciales incorrectas',
        () async {
          when(
            () => mockAuth.signInWithEmailAndPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenAnswer(
            (_) async => throw FirebaseAuthException(
              code: 'wrong-password',
              message: 'Wrong password',
            ),
          );

          await expectLater(
            authService.signInWithEmail(
              email: 'test@test.com',
              password: 'wrong',
            ),
            throwsA(isA<FirebaseAuthException>()),
          );
        },
      );
    });

    group('sendPasswordResetEmail', () {
      test(
        'envía email de restablecimiento con el email normalizado',
        () async {
          when(
            () => mockAuth.sendPasswordResetEmail(email: any(named: 'email')),
          ).thenAnswer((_) async {});

          await authService.sendPasswordResetEmail('  test@test.com  ');

          verify(
            () => mockAuth.sendPasswordResetEmail(email: 'test@test.com'),
          ).called(1);
        },
      );

      test('propaga FirebaseAuthException', () async {
        when(
          () => mockAuth.sendPasswordResetEmail(email: any(named: 'email')),
        ).thenAnswer(
          (_) async => throw FirebaseAuthException(
            code: 'invalid-email',
            message: 'Invalid email',
          ),
        );

        await expectLater(
          authService.sendPasswordResetEmail('bad-email'),
          throwsA(isA<FirebaseAuthException>()),
        );
      });
    });

    group('signInWithGoogle', () {
      test('devuelve null si el usuario cancela (lightweight)', () async {
        when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(false);
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(
          () => mockGoogleSignIn.attemptLightweightAuthentication(),
        ).thenAnswer((_) async => null);

        final result = await authService.signInWithGoogle();
        expect(result, isNull);
      });

      test(
        'no crea perfil para nuevos usuarios de Google (lo hace UsernameSetupScreen)',
        () async {
          final mockGoogleUser = MockGoogleSignInAccount();
          final mockGoogleAuth = MockGoogleSignInAuthentication();
          final mockUser = MockUser();
          final mockCredential = MockUserCredential();

          when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(false);
          when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
          when(
            () => mockGoogleSignIn.attemptLightweightAuthentication(),
          ).thenAnswer((_) async => mockGoogleUser);
          when(() => mockGoogleUser.authentication).thenReturn(mockGoogleAuth);
          when(() => mockGoogleUser.displayName).thenReturn('Google User');
          when(() => mockGoogleAuth.idToken).thenReturn('id_token_123');
          when(
            () => mockAuth.signInWithCredential(any()),
          ).thenAnswer((_) async => mockCredential);
          when(() => mockCredential.user).thenReturn(mockUser);
          when(() => mockUser.uid).thenReturn('google_uid');
          when(() => mockUser.email).thenReturn('google@test.com');
          when(() => mockUser.displayName).thenReturn('Google User');
          when(
            () => mockUserService.userExists(any()),
          ).thenAnswer((_) async => false);

          final result = await authService.signInWithGoogle();

          expect(result, mockUser);
          verify(
            () => mockGoogleSignIn.attemptLightweightAuthentication(),
          ).called(1);
          verifyNever(() => mockGoogleSignIn.authenticate());
          verifyNever(
            () => mockUserService.createUserProfile(
              displayName: any(named: 'displayName'),
              username: any(named: 'username'),
            ),
          );
        },
      );

      test(
        'usa authenticate en iOS para mostrar el flujo interactivo',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          final mockGoogleUser = MockGoogleSignInAccount();
          final mockGoogleAuth = MockGoogleSignInAuthentication();
          final mockUser = MockUser();
          final mockCredential = MockUserCredential();

          when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(true);
          when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
          when(
            () => mockGoogleSignIn.authenticate(),
          ).thenAnswer((_) async => mockGoogleUser);
          when(() => mockGoogleUser.authentication).thenReturn(mockGoogleAuth);
          when(() => mockGoogleAuth.idToken).thenReturn('id_token_123');
          when(
            () => mockAuth.signInWithCredential(any()),
          ).thenAnswer((_) async => mockCredential);
          when(() => mockCredential.user).thenReturn(mockUser);
          when(() => mockUser.uid).thenReturn('google_uid');
          when(() => mockUser.email).thenReturn('google@test.com');
          when(() => mockUser.displayName).thenReturn('Google User');
          when(
            () => mockUserService.userExists(any()),
          ).thenAnswer((_) async => true);
          when(
            () => mockUserService.updateLastLogin(any()),
          ).thenAnswer((_) async {});

          final result = await authService.signInWithGoogle();

          expect(result, mockUser);
          verify(() => mockGoogleSignIn.authenticate()).called(1);
          verifyNever(
            () => mockGoogleSignIn.attemptLightweightAuthentication(),
          );
        },
      );

      test('procesa una sola vez el resultado móvil aunque authenticate emita un evento', () async {
        final authenticationEvents =
            StreamController<GoogleSignInAuthenticationEvent>.broadcast(
              sync: true,
            );
        mockGoogleSignIn = MockGoogleSignIn(
          authenticationEvents: authenticationEvents.stream,
        );
        authService = AuthService(
          mockUserService,
          auth: mockAuth,
          googleSignIn: mockGoogleSignIn,
          notificationService: mockNotificationService,
        );
        addTearDown(() async {
          await authService.dispose();
          await authenticationEvents.close();
        });

        final mockGoogleUser = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUser = MockUser();
        final mockCredential = MockUserCredential();
        final signInEvent = GoogleSignInAuthenticationEventSignIn(
          user: mockGoogleUser,
        );

        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(true);
        when(() => mockGoogleSignIn.authenticate()).thenAnswer((_) async {
          authenticationEvents.add(signInEvent);
          return mockGoogleUser;
        });
        when(() => mockGoogleUser.authentication).thenReturn(mockGoogleAuth);
        when(() => mockGoogleAuth.idToken).thenReturn('id_token_123');
        when(() => mockAuth.signInWithCredential(any()))
            .thenAnswer((_) async => mockCredential);
        when(() => mockCredential.user).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn('google_uid');
        when(() => mockUserService.userExists('google_uid'))
            .thenAnswer((_) async => true);
        when(() => mockUserService.updateLastLogin('google_uid'))
            .thenAnswer((_) async {});

        final result = await authService.signInWithGoogle();

        expect(result, mockUser);
        verify(() => mockAuth.signInWithCredential(any())).called(1);
        verify(() => mockUserService.updateLastLogin('google_uid')).called(1);
      });

      test('actualiza lastLogin si ya existe el usuario', () async {
        final mockGoogleUser = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUser = MockUser();
        final mockCredential = MockUserCredential();

        when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(false);
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(
          () => mockGoogleSignIn.attemptLightweightAuthentication(),
        ).thenAnswer((_) async => mockGoogleUser);
        when(() => mockGoogleUser.authentication).thenReturn(mockGoogleAuth);
        when(() => mockGoogleAuth.idToken).thenReturn('id_token_123');
        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenAnswer((_) async => mockCredential);
        when(() => mockCredential.user).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn('google_uid');
        when(() => mockUser.email).thenReturn('google@test.com');
        when(() => mockUser.displayName).thenReturn('Google User');
        when(
          () => mockUserService.userExists(any()),
        ).thenAnswer((_) async => true);
        when(
          () => mockUserService.updateLastLogin(any()),
        ).thenAnswer((_) async {});

        final result = await authService.signInWithGoogle();

        expect(result, mockUser);
        verify(() => mockUserService.updateLastLogin('google_uid')).called(1);
        verifyNever(
          () => mockUserService.createUserProfile(
            displayName: any(named: 'displayName'),
            username: any(named: 'username'),
          ),
        );
      });

      test('usa lightweight auth si no soporta authenticate', () async {
        final mockGoogleUser = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUser = MockUser();
        final mockCredential = MockUserCredential();

        when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(false);
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(
          () => mockGoogleSignIn.attemptLightweightAuthentication(),
        ).thenAnswer((_) async => mockGoogleUser);
        when(() => mockGoogleUser.authentication).thenReturn(mockGoogleAuth);
        when(() => mockGoogleUser.displayName).thenReturn('User');
        when(() => mockGoogleAuth.idToken).thenReturn('token');
        when(
          () => mockAuth.signInWithCredential(any()),
        ).thenAnswer((_) async => mockCredential);
        when(() => mockCredential.user).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn('uid');
        when(() => mockUser.email).thenReturn('e@t.com');
        when(() => mockUser.displayName).thenReturn('User');
        when(
          () => mockUserService.userExists(any()),
        ).thenAnswer((_) async => true);
        when(
          () => mockUserService.updateLastLogin(any()),
        ).thenAnswer((_) async {});

        await authService.signInWithGoogle();

        verify(
          () => mockGoogleSignIn.attemptLightweightAuthentication(),
        ).called(1);
        verifyNever(() => mockGoogleSignIn.authenticate());
      });
    });

    group('Google authenticationEvents', () {
      test('procesa mediante el stream los resultados del botón web', () async {
        final authenticationEvents =
            StreamController<GoogleSignInAuthenticationEvent>.broadcast();
        mockGoogleSignIn = MockGoogleSignIn(
          authenticationEvents: authenticationEvents.stream,
        );
        authService = AuthService(
          mockUserService,
          auth: mockAuth,
          googleSignIn: mockGoogleSignIn,
          notificationService: mockNotificationService,
        );
        addTearDown(() async {
          await authService.dispose();
          await authenticationEvents.close();
        });

        final processed = Completer<void>();
        final mockGoogleUser = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUser = MockUser();
        final mockCredential = MockUserCredential();

        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(() => mockGoogleUser.authentication).thenReturn(mockGoogleAuth);
        when(() => mockGoogleAuth.idToken).thenReturn('web_id_token');
        when(() => mockAuth.signInWithCredential(any()))
            .thenAnswer((_) async => mockCredential);
        when(() => mockCredential.user).thenReturn(mockUser);
        when(() => mockUser.uid).thenReturn('web_uid');
        when(() => mockUserService.userExists('web_uid'))
            .thenAnswer((_) async => true);
        when(() => mockUserService.updateLastLogin('web_uid'))
            .thenAnswer((_) async {
              processed.complete();
            });

        await authService.initializeGoogleSignInForWeb();
        authenticationEvents.add(
          GoogleSignInAuthenticationEventSignIn(user: mockGoogleUser),
        );
        await processed.future;

        verify(() => mockAuth.signInWithCredential(any())).called(1);
        verify(() => mockUserService.updateLastLogin('web_uid')).called(1);
      });
    });

    group('reauthenticateWithGoogle', () {
      test(
        'no inicia sesión desde el evento antes de validar la cuenta',
        () async {
          final authenticationEvents =
              StreamController<GoogleSignInAuthenticationEvent>.broadcast(
                sync: true,
              );
          mockGoogleSignIn = MockGoogleSignIn(
            authenticationEvents: authenticationEvents.stream,
          );
          authService = AuthService(
            mockUserService,
            auth: mockAuth,
            googleSignIn: mockGoogleSignIn,
            notificationService: mockNotificationService,
          );
          addTearDown(() async {
            await authService.dispose();
            await authenticationEvents.close();
          });

          final currentUser = MockUser();
          final wrongGoogleUser = MockGoogleSignInAccount();
          final wrongGoogleAuth = MockGoogleSignInAuthentication();
          final wrongFirebaseUser = MockUser();
          final wrongCredential = MockUserCredential();

          when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
          when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(true);
          when(() => mockGoogleSignIn.authenticate()).thenAnswer((_) async {
            authenticationEvents.add(
              GoogleSignInAuthenticationEventSignIn(user: wrongGoogleUser),
            );
            return wrongGoogleUser;
          });
          when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
          when(() => wrongGoogleUser.email).thenReturn('other@example.com');
          when(() => wrongGoogleUser.authentication)
              .thenReturn(wrongGoogleAuth);
          when(() => wrongGoogleAuth.idToken).thenReturn('wrong_id_token');
          when(() => mockAuth.currentUser).thenReturn(currentUser);
          when(() => currentUser.email).thenReturn('current@example.com');
          when(() => mockAuth.signInWithCredential(any()))
              .thenAnswer((_) async => wrongCredential);
          when(() => wrongCredential.user).thenReturn(wrongFirebaseUser);
          when(() => wrongFirebaseUser.uid).thenReturn('wrong_uid');
          when(() => mockUserService.userExists('wrong_uid'))
              .thenAnswer((_) async => false);

          await expectLater(
            authService.reauthenticateWithGoogle(),
            throwsA(isA<GoogleAccountMismatchException>()),
          );

          verifyNever(() => mockAuth.signInWithCredential(any()));
          verify(() => mockGoogleSignIn.signOut()).called(1);
        },
      );
    });

    group('signOut', () {
      setUp(() async {
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        await authService.initializeGoogleSignInForWeb();
        addTearDown(authService.dispose);
      });

      test('limita la espera de FCM y Google en paralelo', () async {
        final tokenCleanup = Completer<void>();
        final googleCleanup = Completer<void>();
        when(() => mockNotificationService.clearToken())
            .thenAnswer((_) => tokenCleanup.future);
        when(() => mockGoogleSignIn.signOut())
            .thenAnswer((_) => googleCleanup.future);
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        final signOut = authService.signOut();
        await Future<void>.delayed(Duration.zero);
        verify(() => mockNotificationService.clearToken()).called(1);
        verify(() => mockGoogleSignIn.signOut()).called(1);
        await signOut.timeout(const Duration(seconds: 3));

        verify(() => mockAuth.signOut()).called(1);
        // Errors arriving after the deadline must still be handled.
        tokenCleanup.completeError(StateError('late Firestore failure'));
        googleCleanup.completeError(StateError('late Google failure'));
        await Future<void>.delayed(Duration.zero);
      });

      test('cierra Firebase aunque fallen las dos limpiezas', () async {
        when(() => mockNotificationService.clearToken())
            .thenThrow(StateError('FCM failed'));
        when(() => mockGoogleSignIn.signOut())
            .thenThrow(StateError('Google failed'));
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await authService.signOut();

        verify(() => mockAuth.signOut()).called(1);
      });

      test('propaga un fallo del cierre local de Firebase', () async {
        when(() => mockNotificationService.clearToken())
            .thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        final failure = StateError('local sign-out failed');
        when(() => mockAuth.signOut()).thenThrow(failure);

        await expectLater(authService.signOut(), throwsA(same(failure)));
      });

      test('cierra sesión en Google y Firebase, limpia FCM token', () async {
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});
        when(() => mockNotificationService.clearToken())
            .thenAnswer((_) async {});

        await authService.signOut();

        verify(() => mockNotificationService.clearToken()).called(1);
        verify(() => mockGoogleSignIn.signOut()).called(1);
        verify(() => mockAuth.signOut()).called(1);
      });

      test('permite omitir la limpieza cliente del token FCM', () async {
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});

        await authService.signOut(clearNotificationToken: false);

        verifyNever(() => mockNotificationService.clearToken());
        verify(() => mockGoogleSignIn.signOut()).called(1);
        verify(() => mockAuth.signOut()).called(1);
      });
    });
  });
}
