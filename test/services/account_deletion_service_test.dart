// ignore_for_file: subtype_of_sealed_class
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/account_deletion_service.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseAuth auth;
  late MockFirebaseFirestore firestore;
  late MockFirebaseFunctions functions;
  late MockUser user;
  late MockHttpsCallable callable;
  late MockHttpsCallableResult<dynamic> result;
  late AccountDeletionService service;

  setUp(() {
    auth = MockFirebaseAuth();
    firestore = MockFirebaseFirestore();
    functions = MockFirebaseFunctions();
    user = MockUser();
    callable = MockHttpsCallable();
    result = MockHttpsCallableResult<dynamic>();

    when(() => auth.currentUser).thenReturn(user);
    when(() => user.getIdToken(true)).thenAnswer((_) async => 'fresh-token');
    when(
      () => functions.httpsCallable('requestAccountDeletion'),
    ).thenReturn(callable);
    when(() => callable.call<dynamic>()).thenAnswer((_) async => result);
    when(
      () => result.data,
    ).thenReturn({'status': 'requested', 'phase': 'freeze'});

    service = AccountDeletionService(
      auth: auth,
      firestore: firestore,
      functions: functions,
    );
  });

  test('refreshes auth token and starts the durable backend job', () async {
    final progress = await service.requestDeletion();

    expect(progress.status, 'requested');
    expect(progress.phase, 'freeze');
    verify(() => user.getIdToken(true)).called(1);
    verify(() => callable.call<dynamic>()).called(1);
  });

  test('requires an authenticated user', () async {
    when(() => auth.currentUser).thenReturn(null);

    expect(service.requestDeletion, throwsStateError);
    verifyNever(() => functions.httpsCallable(any()));
  });
}
