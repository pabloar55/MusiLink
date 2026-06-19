import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
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
              uid: any(named: 'uid'),
              email: any(named: 'email'),
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
        ).thenThrow(
          FirebaseAuthException(
            code: 'email-already-in-use',
            message: 'Email already in use',
          ),
        );

        expect(
          () => authService.registerWithEmail(
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
          ).thenThrow(
            FirebaseAuthException(
              code: 'wrong-password',
              message: 'Wrong password',
            ),
          );

          expect(
            () => authService.signInWithEmail(
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
        ).thenThrow(
          FirebaseAuthException(
            code: 'invalid-email',
            message: 'Invalid email',
          ),
        );

        expect(
          () => authService.sendPasswordResetEmail('bad-email'),
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

          when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(true);
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
              uid: any(named: 'uid'),
              email: any(named: 'email'),
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

      test('actualiza lastLogin si ya existe el usuario', () async {
        final mockGoogleUser = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUser = MockUser();
        final mockCredential = MockUserCredential();

        when(() => mockGoogleSignIn.supportsAuthenticate()).thenReturn(true);
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
            uid: any(named: 'uid'),
            email: any(named: 'email'),
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

    group('signOut', () {
      test('cierra sesión en Google y Firebase, limpia FCM token', () async {
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        when(() => mockAuth.signOut()).thenAnswer((_) async {});
        when(
          () => mockNotificationService.clearToken(),
        ).thenAnswer((_) async {});

        await authService.signOut();

        verify(() => mockNotificationService.clearToken()).called(1);
        verify(() => mockGoogleSignIn.signOut()).called(1);
        verify(() => mockAuth.signOut()).called(1);
      });
    });
  });
}
