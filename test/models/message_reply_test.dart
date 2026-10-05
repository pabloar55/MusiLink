import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/daily_song_reply.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/message_reply.dart';
import 'package:musi_link/models/track.dart';

import '../helpers/mocks.dart';

void main() {
  test('Firestore y copyWith conservan la cita generada por el backend', () {
    final doc = MockDocumentSnapshot();
    when(() => doc.id).thenReturn('answer');
    when(() => doc.data()).thenReturn({
      'senderId': 'alice',
      'text': 'Claro',
      'type': 'text',
      'replyTo': {
        'messageId': 'original',
        'senderId': 'bob',
        'text': 'Song - Artist',
        'type': 'track',
      },
    });
    final restored = Message.fromFirestore(doc)!
        .copyWith(read: true, delivered: true);
    expect(restored.replyTo!.messageId, 'original');
    expect(restored.replyTo!.senderId, 'bob');
    expect(restored.replyTo!.text, 'Song - Artist');
    expect(restored.replyTo!.isTrack, isTrue);
    expect(restored.toFirestore()['replyTo'], restored.replyTo!.toMap());
  });

  test('ignora citas mal formadas sin descartar el mensaje', () {
    for (final replyTo in [
      null,
      'original',
      {'messageId': '', 'senderId': 'bob'},
      {'messageId': 'original'},
    ]) {
      final doc = MockDocumentSnapshot();
      when(() => doc.id).thenReturn('answer');
      when(
        () => doc.data(),
      ).thenReturn({'senderId': 'alice', 'text': 'Claro', 'replyTo': replyTo});
      final message = Message.fromFirestore(doc)!;
      expect(message.text, 'Claro');
      expect(message.replyTo, isNull);
    }
  });

  test('la cita local resume el mensaje igual que el backend', () {
    final long = Message(
      id: 'long',
      senderId: 'bob',
      text: '🎵' * (MessageReply.maxPreviewChars + 50),
      timestamp: DateTime(2026),
    ).toReply();
    expect(long.messageId, 'long');
    expect(long.senderId, 'bob');
    expect(long.text, '🎵' * MessageReply.maxPreviewChars);
    expect(long.isTrack, isFalse);

    final track = Message(
      id: 'track',
      senderId: 'bob',
      text: 'Song - Artist',
      timestamp: DateTime(2026),
      type: MessageType.track,
      trackData: const Track(title: 'Song', artist: 'Artist', imageUrl: ''),
    ).toReply();
    expect(track.text, 'Song - Artist');
    expect(track.isTrack, isTrue);

    final legacy = Message(
      id: 'legacy',
      senderId: 'bob',
      text: '🎵 “Song” — Artist\n\nMe encanta',
      timestamp: DateTime(2026),
      dailySongReply: DailySongReply.tryFromMap({
        'ownerId': 'alice',
        'publishedAtMicros': 123,
      }),
    ).toReply();
    expect(legacy.text, 'Me encanta');
  });
}
