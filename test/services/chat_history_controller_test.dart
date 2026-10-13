import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/services/chat_history_controller.dart';
import 'package:musi_link/services/chat_service.dart';

class _MockChatService extends Mock implements ChatService {}

void main() {
  late _MockChatService service;
  late List<bool> errors;
  late ChatHistoryController history;

  setUp(() {
    service = _MockChatService();
    errors = [];
    history = ChatHistoryController(
      service: service,
      chatId: 'chat-1',
      onMessages: ({required isFirst}) {},
      onError: ({required unavailable}) => errors.add(unavailable),
    );
    addTearDown(history.dispose);
  });

  test('reports the chat as unavailable when it cannot be opened', () async {
    when(() => service.getDeletedSince('chat-1'))
        .thenThrow(StateError('Offline'));

    await history.start();

    expect(errors, [true]);
    expect(history.isInitialLoading, isFalse);
    verifyNever(
      () => service.getMessages(
        any(),
        since: any(named: 'since'),
        from: any(named: 'from'),
      ),
    );
  });

  test(
    'a stream error fails the pending history request and keeps pagination',
    () async {
      final events = StreamController<List<Message>>.broadcast();
      addTearDown(events.close);
      final loaded = List.generate(
        ChatService.messagesPageSize,
        (i) => Message(
          id: 'message-$i',
          senderId: 'other-user',
          text: 'Message $i',
          timestamp: DateTime(2026, 7, 19, 12, i),
        ),
      );
      final original = Message(
        id: 'old',
        senderId: 'other-user',
        text: 'Long ago',
        timestamp: DateTime(2026, 6),
      );
      when(() => service.getDeletedSince('chat-1'))
          .thenAnswer((_) async => null);
      when(() => service.getMessages('chat-1', from: any(named: 'from')))
          .thenAnswer((_) => events.stream);
      when(() => service.getMessage('chat-1', 'old'))
          .thenAnswer((_) async => original);
      when(
        () => service.loadOlderMessages('chat-1', before: any(named: 'before')),
      ).thenAnswer((_) async => []);

      await history.start();
      events.add(loaded);
      await pumpEventQueue();

      final request = history.loadThrough('old');
      await pumpEventQueue();
      verify(() => service.getMessages('chat-1', from: original.timestamp))
          .called(1);
      expect(history.isLoadingMore, isTrue);

      events.addError(StateError('Offline'), StackTrace.empty);

      expect(await request, isNull);
      expect(errors, [false]);
      expect(history.isLoadingMore, isFalse);
      expect(history.messages, loaded);

      await history.loadMore();
      verify(
        () =>
            service.loadOlderMessages('chat-1', before: loaded.first.timestamp),
      ).called(1);
    },
  );
}
