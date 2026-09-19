// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/terms_acceptance_service.dart';
import 'package:musi_link/utils/terms_and_conditions.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseFirestore firestore;
  late MockFirebaseFunctions functions;
  late MockDocumentSnapshot snapshot;
  late TermsAcceptanceService service;

  setUp(() {
    firestore = MockFirebaseFirestore();
    functions = MockFirebaseFunctions();
    snapshot = MockDocumentSnapshot();
    final privateUsers = MockCollectionReference();
    final privateUser = MockDocumentReference();
    final acceptances = MockCollectionReference();
    final current = MockDocumentReference();
    when(() => firestore.collection('user_private')).thenReturn(privateUsers);
    when(() => privateUsers.doc('alice')).thenReturn(privateUser);
    when(() => privateUser.collection('terms_acceptances'))
        .thenReturn(acceptances);
    when(() => acceptances.doc('current')).thenReturn(current);
    when(() => current.get(const GetOptions(source: Source.server)))
        .thenAnswer((_) async => snapshot);
    service = TermsAcceptanceService(firestore, functions);
  });

  test('solo acepta la versión vigente confirmada por el servidor', () async {
    when(() => snapshot.data())
        .thenReturn({'version': TermsAndConditions.version});
    expect(await service.hasAcceptedCurrentVersion('alice'), isTrue);

    when(() => snapshot.data()).thenReturn({'version': 'old-version'});
    expect(await service.hasAcceptedCurrentVersion('alice'), isFalse);

    when(() => snapshot.data()).thenReturn(null);
    expect(await service.hasAcceptedCurrentVersion('alice'), isFalse);
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

    expect(service.acceptCurrentVersion(), throwsStateError);
  });
}
