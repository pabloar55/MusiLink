import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/auth_service.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseAuth auth;
  late MockUser user;
  late MockGoogleSignIn googleSignIn;
  late AuthService service;

  setUpAll(() {
    registerFallbackValue(GoogleAuthProvider());
    registerFallbackValue(GoogleAuthProvider.credential(idToken: 'fallback'));
  });

  setUp(() {
    auth = MockFirebaseAuth();
    user = MockUser();
    googleSignIn = MockGoogleSignIn();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.email).thenReturn('current@example.com');
    service = AuthService(
      MockUserService(),
      auth: auth,
      googleSignIn: googleSignIn,
      notificationService: MockNotificationService(),
    );
  });

  tearDown(() async {
    await service.dispose();
    verifyNever(() => auth.signInWithCredential(any()));
    verifyNever(() => auth.signOut());
  });

  test('sin sesión no inicia la reautenticación', () async {
    when(() => auth.currentUser).thenReturn(null);

    expect(await service.reauthenticateWithGoogle(), isFalse);
    verifyNever(() => user.reauthenticateWithPopup(any()));
    verifyZeroInteractions(googleSignIn);
  });

  group('web', () {
    test('espera al popup antes de permitir continuar el borrado', () async {
      final popup = Completer<UserCredential>();
      when(() => user.reauthenticateWithPopup(any()))
          .thenAnswer((_) => popup.future);
      var completed = false;

      final result = service.reauthenticateWithGoogle().then((value) {
        completed = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      final provider =
          verify(() => user.reauthenticateWithPopup(captureAny()))
                  .captured
                  .single
              as GoogleAuthProvider;
      expect(provider.parameters['prompt'], 'select_account');
      verifyZeroInteractions(googleSignIn);

      popup.complete(MockUserCredential());
      expect(await result, isTrue);
      verifyNever(() => user.reauthenticateWithCredential(any()));
    });

    for (final code in ['popup-closed-by-user', 'cancelled-popup-request']) {
      test('$code cancela el borrado', () async {
        when(() => user.reauthenticateWithPopup(any()))
            .thenThrow(FirebaseAuthException(code: code));

        expect(await service.reauthenticateWithGoogle(), isFalse);
        verifyZeroInteractions(googleSignIn);
      });
    }

    test('otra cuenta produce el error que muestra ajustes', () async {
      when(() => user.reauthenticateWithPopup(any()))
          .thenThrow(FirebaseAuthException(code: 'user-mismatch'));

      await expectLater(
        service.reauthenticateWithGoogle(),
        throwsA(isA<GoogleAccountMismatchException>()),
      );
      verifyZeroInteractions(googleSignIn);
    });

    for (final code in ['popup-blocked', 'network-request-failed']) {
      test('$code se propaga como error', () async {
        final error = FirebaseAuthException(code: code);
        when(() => user.reauthenticateWithPopup(any())).thenThrow(error);

        await expectLater(
          service.reauthenticateWithGoogle(),
          throwsA(same(error)),
        );
      });
    }
  }, skip: !kIsWeb);

  group('móvil', () {
    setUp(() {
      when(() => googleSignIn.initialize()).thenAnswer((_) async {});
      when(() => googleSignIn.supportsAuthenticate()).thenReturn(true);
    });

    test('reautentica con la credencial de la cuenta actual', () async {
      final account = MockGoogleSignInAccount();
      final authentication = MockGoogleSignInAuthentication();
      when(() => googleSignIn.authenticate()).thenAnswer((_) async => account);
      when(() => account.email).thenReturn('current@example.com');
      when(() => account.authentication).thenReturn(authentication);
      when(() => authentication.idToken).thenReturn('google-id-token');
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => MockUserCredential());

      expect(await service.reauthenticateWithGoogle(), isTrue);
      final credential =
          verify(() => user.reauthenticateWithCredential(captureAny()))
                  .captured
                  .single
              as OAuthCredential;
      expect(credential.idToken, 'google-id-token');
      verifyNever(() => user.reauthenticateWithPopup(any()));
    });

    test('cancelar Google impide continuar el borrado', () async {
      when(() => googleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );

      expect(await service.reauthenticateWithGoogle(), isFalse);
      verifyNever(() => user.reauthenticateWithCredential(any()));
    });
  }, skip: kIsWeb);
}
