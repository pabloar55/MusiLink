import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/services/chat_history_store.dart';

List<Message> _messages(int count) => [
  for (var index = 0; index < count; index += 1)
    Message(
      id: 'message-$index',
      senderId: 'other',
      text: '$index',
      timestamp: DateTime(2026, 1, 1, 0, index),
    ),
];

void main() {
  late ChatHistoryStore store;

  setUp(() => store = ChatHistoryStore(null, maxMessages: 3));

  test('guarda solo la última página y los chats más recientes', () {
    store.write('me', 'chat-0', null, _messages(5));
    expect(store.read('me', 'chat-0')!.messages.map((message) => message.id), [
      'message-2',
      'message-3',
      'message-4',
    ]);

    for (var index = 1; index <= ChatHistoryStore.maxChats; index += 1) {
      store.write('me', 'chat-$index', null, _messages(1));
    }
    expect(store.read('me', 'chat-0'), isNull);
    expect(store.read('me', 'chat-1'), isNotNull);
    expect(store.read('other', 'chat-1'), isNull);
  });

  test('invalidar descarta el historial y las cargas que lo esperaban', () {
    final token = store.token('me', 'chat');
    store.write('me', 'chat', null, _messages(1));
    expect(store.isCurrent('me', 'chat', token), isTrue);

    store.invalidate('me', 'chat');

    expect(store.inMemory('me', 'chat'), isNull);
    expect(store.isCurrent('me', 'chat', token), isFalse);
  });

  test('solo invalida cuando cambia el filtro de borrado', () {
    final since = DateTime(2026);
    store.write('me', 'chat', since, _messages(1));

    store.invalidateIfSinceChanged('me', 'chat', since);
    expect(store.inMemory('me', 'chat'), isNotNull);

    store.invalidateIfSinceChanged('me', 'chat', null);
    expect(store.inMemory('me', 'chat'), isNull);
  });

  test('no repite una precarga que sigue en curso', () async {
    final loading = Completer<void>();
    var loads = 0;
    Future<void> load() {
      loads += 1;
      return loading.future;
    }

    final first = store.prefetch('me', 'chat', null, load);
    final second = store.prefetch('me', 'chat', null, load);
    loading.complete();
    await Future.wait([first, second]);
    expect(loads, 1);

    await store.prefetch('me', 'chat', null, () async => loads += 1);
    expect(loads, 2);
  });
}
