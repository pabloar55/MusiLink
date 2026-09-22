// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/terms_acceptance_service.dart';
import 'package:musi_link/utils/terms_and_conditions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseFirestore firestore;
  late MockFirebaseFunctions functions;
  late MockDocumentSnapshot snapshot;
  late TermsAcceptanceService service;
  late SharedPreferences prefs;
  late MockFirebaseAuth auth;
  late MockDocumentReference current;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => user.uid).thenReturn('alice');
    when(() => auth.currentUser).thenReturn(user);
    firestore = MockFirebaseFirestore();
    functions = MockFirebaseFunctions();
    snapshot = MockDocumentSnapshot();
    final privateUsers = MockCollectionReference();
    final privateUser = MockDocumentReference();
    final acceptances = MockCollectionReference();
    current = MockDocumentReference();
    when(() => firestore.collection('user_private')).thenReturn(privateUsers);
    when(() => privateUsers.doc('alice')).thenReturn(privateUser);
    when(() => privateUser.collection('terms_acceptances'))
        .thenReturn(acceptances);
    when(() => acceptances.doc('current')).thenReturn(current);
    when(() => current.get(const GetOptions(source: Source.server)))
        .thenAnswer((_) async => snapshot);
    service = TermsAcceptanceService(
      firestore,
      functions,
      prefs: prefs,
      auth: auth,
    );
  });

  test('la caché exige el mismo usuario y la versión vigente', () async {
    expect(service.hasCachedAcceptance('alice'), isFalse);
    await prefs.setString('terms_accepted_version_alice', 'old-version');
    expect(service.hasCachedAcceptance('alice'), isFalse);
    await prefs.setString(
      'terms_accepted_version_alice',
      TermsAndConditions.version,
    );
    expect(service.hasCachedAcceptance('alice'), isTrue);
    expect(service.hasCachedAcceptance('bob'), isFalse);
    verifyNever(() => current.get(const GetOptions(source: Source.server)));
  });

  test('solo acepta la versión vigente confirmada por el servidor', () async {
    when(() => snapshot.data())
        .thenReturn({'version': TermsAndConditions.version});
    expect(await service.hasAcceptedCurrentVersion('alice'), isTrue);
    final restarted = TermsAcceptanceService(
      firestore,
      functions,
      prefs: prefs,
      auth: auth,
    );
    expect(restarted.hasCachedAcceptance('alice'), isTrue);

    when(() => snapshot.data()).thenReturn({'version': 'old-version'});
    expect(await service.hasAcceptedCurrentVersion('alice'), isFalse);
    expect(service.hasCachedAcceptance('alice'), isFalse);

    when(() => snapshot.data()).thenReturn(null);
    expect(await service.hasAcceptedCurrentVersion('alice'), isFalse);
  });

  test(
    'un error de red conserva la aceptación previamente confirmada',
    () async {
      await prefs.setString(
        'terms_accepted_version_alice',
        TermsAndConditions.version,
      );
      when(() => current.get(const GetOptions(source: Source.server)))
          .thenThrow(StateError('offline'));
      await expectLater(
        service.hasAcceptedCurrentVersion('alice'),
        throwsStateError,
      );
      expect(service.hasCachedAcceptance('alice'), isTrue);
      expect(service.hasCachedAcceptance('bob'), isFalse);
    },
  );

  testWidgets('la consulta sin respuesta termina sin borrar la caché', (
    tester,
  ) async {
    await prefs.setString(
      'terms_accepted_version_alice',
      TermsAndConditions.version,
    );
    final pending = Completer<MockDocumentSnapshot>();
    when(() => current.get(const GetOptions(source: Source.server)))
        .thenAnswer((_) => pending.future);
    final check = expectLater(
      service.hasAcceptedCurrentVersion('alice'),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 10));
    await check;
    expect(service.hasCachedAcceptance('alice'), isTrue);
    when(() => snapshot.data()).thenReturn(null);
    pending.complete(snapshot);
    await tester.pump();
    expect(service.hasCachedAcceptance('alice'), isTrue);
  });

  test(
    'envía la versión publicada y exige confirmación de la callable',
    () async {
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult<Map<String, dynamic>>();
      when(() => functions.httpsCallable('acceptTerms')).thenReturn(callable);
      when(() => result.data)
          .thenReturn({'version': TermsAndConditions.version});
      when(() => callable.call<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => result);

      await service.acceptCurrentVersion();
      expect(service.hasCachedAcceptance('alice'), isTrue);
      expect(service.hasCachedAcceptance('bob'), isFalse);

      final payload =
          verify(() => callable.call<Map<String, dynamic>>(captureAny()))
                  .captured
                  .single
              as Map<String, dynamic>;
      expect(payload, {'version': TermsAndConditions.version});
    },
  );

  test('rechaza una respuesta con otra versión', () async {
    final callable = MockHttpsCallable();
    final result = MockHttpsCallableResult<Map<String, dynamic>>();
    when(() => functions.httpsCallable('acceptTerms')).thenReturn(callable);
    when(() => result.data).thenReturn({'version': 'old-version'});
    when(() => callable.call<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => result);

    await expectLater(service.acceptCurrentVersion(), throwsStateError);
    expect(service.hasCachedAcceptance('alice'), isFalse);
  });

  test(
    'una lectura antigua no borra una aceptación recién confirmada',
    () async {
      final pending = Completer<MockDocumentSnapshot>();
      when(() => current.get(const GetOptions(source: Source.server)))
          .thenAnswer((_) => pending.future);
      final check = service.hasAcceptedCurrentVersion('alice');
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult<Map<String, dynamic>>();
      when(() => functions.httpsCallable('acceptTerms')).thenReturn(callable);
      when(() => result.data)
          .thenReturn({'version': TermsAndConditions.version});
      when(() => callable.call<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => result);
      await service.acceptCurrentVersion();
      when(() => snapshot.data()).thenReturn(null);
      pending.complete(snapshot);
      expect(await check, isTrue);
      expect(service.hasCachedAcceptance('alice'), isTrue);
    },
  );

  test(
    'no guarda la confirmación si cambia la cuenta durante la llamada',
    () async {
      final pending =
          Completer<MockHttpsCallableResult<Map<String, dynamic>>>();
      final callable = MockHttpsCallable();
      final result = MockHttpsCallableResult<Map<String, dynamic>>();
      when(() => functions.httpsCallable('acceptTerms')).thenReturn(callable);
      when(() => result.data)
          .thenReturn({'version': TermsAndConditions.version});
      when(() => callable.call<Map<String, dynamic>>(any()))
          .thenAnswer((_) => pending.future);
      final accept = service.acceptCurrentVersion();
      final other = MockUser();
      when(() => other.uid).thenReturn('bob');
      when(() => auth.currentUser).thenReturn(other);
      pending.complete(result);
      await expectLater(accept, throwsStateError);
      expect(service.hasCachedAcceptance('alice'), isFalse);
      expect(service.hasCachedAcceptance('bob'), isFalse);
    },
  );
}
