import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/group_chat_service.dart';
import 'package:musi_link/services/service_exceptions.dart';

import '../helpers/mocks.dart';

class MockChatService extends Mock implements ChatService {}

void main() {
  late MockFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late MockFirebaseFunctions functions;
  late MockCollectionReference chatsRef;
  late MockDocumentReference groupRef;
  late MockHttpsCallable callable;
  late List<(String, String)> left;
  late MockUser? currentUser;
  late GroupChatService service;

  setUp(() {
    firestore = MockFirebaseFirestore();
    auth = MockFirebaseAuth();
    functions = MockFirebaseFunctions();
    chatsRef = MockCollectionReference();
    groupRef = MockDocumentReference();
    callable = MockHttpsCallable();
    left = [];
    final user = MockUser();
    when(() => user.uid).thenReturn('me');
    currentUser = user;
    when(() => auth.currentUser).thenAnswer((_) => currentUser);
    when(() => firestore.collection('chats')).thenReturn(chatsRef);
    when(() => chatsRef.doc('group-1')).thenReturn(groupRef);
    when(() => functions.httpsCallable(any())).thenReturn(callable);
    when(() => callable.call<void>(any()))
        .thenAnswer((_) async => MockHttpsCallableResult<void>());
    service = GroupChatService(
      firestore: firestore,
      auth: auth,
      functions: functions,
      onGroupLeft: (uid, chatId) => left.add((uid, chatId)),
    );
  });

  MockFirebaseFunctionsException failure(String code) {
    final exception = MockFirebaseFunctionsException();
    when(() => exception.code).thenReturn(code);
    return exception;
  }

  group('leaveGroupChat', () {
    test('avisa de la salida con el usuario que la pidió', () async {
      when(() => callable.call<void>(any())).thenAnswer((_) async {
        // La sesión cambia mientras el backend procesa la salida.
        currentUser = null;
        return MockHttpsCallableResult<void>();
      });

      await service.leaveGroupChat('group-1');

      verify(() => functions.httpsCallable('leaveGroupChat')).called(1);
      verify(() => callable.call<void>({'chatId': 'group-1'})).called(1);
      expect(left, [('me', 'group-1')]);
    });

    test('no avisa si el backend rechaza la salida', () async {
      final exception = failure('internal');
      when(() => callable.call<void>(any())).thenThrow(exception);

      await expectLater(
        service.leaveGroupChat('group-1'),
        throwsA(same(exception)),
      );
      expect(left, isEmpty);
    });
  });

  test('crear y añadir miembros traducen el límite de peticiones', () async {
    final throttled = failure('resource-exhausted');
    when(() => callable.call<void>(any())).thenThrow(throttled);

    await expectLater(
      service.createGroupChat(
        chatId: 'group-1',
        name: 'Music friends',
        participantIds: ['bob'],
      ),
      throwsA(isA<RateLimitedException>()),
    );
    await expectLater(
      service.addGroupMembers('group-1', ['bob']),
      throwsA(isA<RateLimitedException>()),
    );
  });

  group('markGroupMessagesAsRead', () {
    final shown = DateTime(2026, 1, 2);
    late FakeTransaction transaction;
    late MockDocumentSnapshot snapshot;

    setUp(() {
      transaction = FakeTransaction();
      snapshot = MockDocumentSnapshot();
      transaction.getResult = snapshot;
      firestore.fakeTransaction = transaction;
    });

    test('marca como leído hasta el último mensaje mostrado', () async {
      when(() => snapshot.data()).thenReturn({
        'type': 'group',
        'lastMessageTime': Timestamp.fromDate(shown),
      });

      await service.markGroupMessagesAsRead('group-1', shown);

      expect(transaction.updates.single.value, {
        'lastReadAt.me': Timestamp.fromDate(shown),
        'unreadCounts.me': 0,
      });
    });

    test('no marca si hay un mensaje más nuevo sin mostrar', () async {
      when(() => snapshot.data()).thenReturn({
        'type': 'group',
        'lastMessageTime': Timestamp.fromDate(DateTime(2026, 1, 3)),
      });

      await service.markGroupMessagesAsRead('group-1', shown);

      expect(transaction.updates, isEmpty);
    });
  });

  test('al salir de un grupo se olvida su historial guardado', () async {
    final chatService = MockChatService();
    final container = ProviderContainer(
      overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        firebaseAuthProvider.overrideWithValue(auth),
        firebaseFunctionsProvider.overrideWithValue(functions),
        chatServiceProvider.overrideWithValue(chatService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(groupChatServiceProvider).leaveGroupChat('group-1');

    verify(() => chatService.forgetHistory('me', 'group-1')).called(1);
  });
}
