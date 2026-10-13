import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/services/pending_messages.dart';

Message _message(String id) => Message(
  id: id,
  senderId: 'me',
  text: id,
  timestamp: DateTime(2026),
  isPending: true,
);

void main() {
  late PendingMessages pending;
  late List<(String, String)> changes;

  setUp(() {
    pending = PendingMessages();
    changes = [];
    pending.changes.listen(changes.add);
  });

  test('añade los pendientes sin duplicar los ya confirmados', () async {
    final confirmed = _message('first');
    pending.add('me', 'chat', _message('first'));
    pending.add('me', 'chat', _message('second'));

    final merged = pending.merge('me', 'chat', [confirmed]);

    expect(merged.map((message) => message.id), ['first', 'second']);
    expect(merged.first, same(confirmed));
    expect(pending.merge('me', 'other', [confirmed]), [confirmed]);
    await pumpEventQueue();
    expect(changes, [('me', 'chat'), ('me', 'chat')]);
  });

  test('un envío confirmado ya no se puede retirar', () async {
    final discard = pending.add('me', 'chat', _message('first'));
    pending.confirm('me', 'chat', [_message('first')]);

    expect(discard(), isFalse);
    expect(pending.hasAny('me', 'chat'), isFalse);
    await pumpEventQueue();
    expect(changes, [('me', 'chat')]);
  });

  test('un envío fallido se retira y avisa del cambio', () async {
    final discard = pending.add('me', 'chat', _message('first'));

    expect(discard(), isTrue);
    expect(pending.merge('me', 'chat', []), isEmpty);
    await pumpEventQueue();
    expect(changes, [('me', 'chat'), ('me', 'chat')]);
  });

  test('vaciar no da por confirmado un envío en curso', () {
    final discard = pending.add('me', 'chat', _message('first'));

    pending.clear();

    expect(pending.hasAny('me', 'chat'), isFalse);
    expect(discard(), isTrue);
  });
}
