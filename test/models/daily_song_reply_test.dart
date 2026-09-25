import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/daily_song_reply.dart';
import 'package:musi_link/models/message.dart';

import '../helpers/mocks.dart';

void main() {
  test('Firestore y copyWith conservan el contexto y el texto normal', () {
    final original = Message(
      id: 'reply',
      senderId: 'alice',
      text: 'Me encanta',
      timestamp: DateTime.now(),
      dailySongReply: const DailySongReply(
        ownerId: 'bob',
        publishedAtMicros: 123,
      ),
    );
    final doc = MockDocumentSnapshot();
    when(() => doc.id).thenReturn('reply');
    when(() => doc.data()).thenReturn(original.toFirestore());
    final restored = Message.fromFirestore(doc)!
        .copyWith(read: true, delivered: true);
    expect(restored.bodyText, 'Me encanta');
    expect(restored.dailySongReply!.toMap(), original.dailySongReply!.toMap());
    expect(restored.read, isTrue);
  });

  test(
    'el formato antiguo elimina el prefijo solo en respuestas identificadas',
    () {
      const text = '🎵 “Song” — Artist\n\nMe encanta\n\nMucho';
      final legacy = Message(
        id: 'reply',
        senderId: 'alice',
        text: text,
        timestamp: DateTime.now(),
        dailySongReply: DailySongReply.tryFromMap({
          'ownerId': 'bob',
          'publishedAtMicros': 123,
        }),
      );
      expect(legacy.bodyText, 'Me encanta\n\nMucho');
      final plain = Message(
        id: 'text',
        senderId: 'alice',
        text: text,
        timestamp: DateTime.now(),
      );
      expect(plain.bodyText, text);
      final modern = Message(
        id: 'reply',
        senderId: 'alice',
        text: text,
        timestamp: DateTime.now(),
        dailySongReply: const DailySongReply(
          ownerId: 'bob',
          publishedAtMicros: 123,
        ),
      );
      expect(modern.bodyText, text);
    },
  );

  test('ignora referencias de respuesta malformadas', () {
    for (final value in [
      null,
      true,
      {},
      {'ownerId': 1, 'publishedAtMicros': 123},
      {'ownerId': 'bob', 'publishedAtMicros': '123'},
    ]) {
      expect(DailySongReply.tryFromMap(value), isNull);
    }
  });
}
