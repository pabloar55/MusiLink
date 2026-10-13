import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/session_scope_provider.dart';
import 'package:musi_link/services/chat_service.dart';

import '../helpers/mocks.dart';

class MockChatService extends Mock implements ChatService {}

void main() {
  late MockFirebaseAuth auth;
  late StreamController<User?> authState;
  late MockChatService chatService;
  late ProviderContainer container;

  MockUser userWithUid(String uid) {
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    return user;
  }

  setUp(() {
    auth = MockFirebaseAuth();
    authState = StreamController<User?>();
    chatService = MockChatService();
    when(() => chatService.getChats()).thenAnswer((_) => const Stream.empty());
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        authStateProvider.overrideWith((_) => authState.stream),
        chatServiceProvider.overrideWithValue(chatService),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await authState.close();
    });
  });

  test('usa la sesión restaurada hasta que el stream emite', () {
    final alice = userWithUid('alice');
    when(() => auth.currentUser).thenReturn(alice);

    expect(container.read(sessionUidProvider), 'alice');
  });

  test(
    'solo reconstruye a quien lo observa cuando cambia el usuario',
    () async {
      final alice = userWithUid('alice');
      when(() => auth.currentUser).thenReturn(alice);
      final uids = <String?>[];
      container.listen(
        sessionUidProvider,
        (_, uid) => uids.add(uid),
        fireImmediately: true,
      );
      container.listen(chatsProvider, (_, _) {});

      // El stream confirma la misma sesión: nadie se vuelve a suscribir.
      authState.add(alice);
      await pumpEventQueue();
      verify(() => chatService.getChats()).called(1);

      authState.add(userWithUid('bob'));
      await pumpEventQueue();
      verify(() => chatService.getChats()).called(1);

      when(() => auth.currentUser).thenReturn(null);
      authState.add(null);
      await pumpEventQueue();
      verifyNever(() => chatService.getChats());
      expect(uids, ['alice', 'bob', null]);
    },
  );
}
