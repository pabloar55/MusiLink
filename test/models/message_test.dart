import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/track.dart';

void main() {
  group('Message', () {
    final timestamp = DateTime(2025, 6, 15, 14, 30);

    group('constructor', () {
      test('crea Message de texto con valores por defecto', () {
        final message = Message(
          id: 'msg1',
          senderId: 'user1',
          text: 'Hola!',
          timestamp: timestamp,
        );

        expect(message.id, 'msg1');
        expect(message.senderId, 'user1');
        expect(message.text, 'Hola!');
        expect(message.read, false);
        expect(message.delivered, false);
        expect(message.isPending, false);
        expect(message.type, MessageType.text);
        expect(message.trackData, isNull);
        expect(message.reactions, isEmpty);
        expect(message.isTrack, false);
      });

      test('crea Message de tipo track', () {
        const track = Track(
          title: 'Test Song',
          artist: 'Test Artist',
          imageUrl: 'url',
        );

        final message = Message(
          id: 'msg2',
          senderId: 'user1',
          text: 'Test Song - Test Artist',
          timestamp: timestamp,
          type: MessageType.track,
          trackData: track,
        );

        expect(message.isTrack, true);
        expect(message.trackData, isNotNull);
        expect(message.trackData!.title, 'Test Song');
      });
    });

    group('isTrack', () {
      test('devuelve true para MessageType.track', () {
        final message = Message(
          id: '1',
          senderId: 'u1',
          text: '',
          timestamp: timestamp,
          type: MessageType.track,
        );

        expect(message.isTrack, true);
      });

      test('devuelve false para MessageType.text', () {
        final message = Message(
          id: '1',
          senderId: 'u1',
          text: '',
          timestamp: timestamp,
          type: MessageType.text,
        );

        expect(message.isTrack, false);
      });
    });

    group('copyWith', () {
      test('cambia solo el campo read', () {
        final original = Message(
          id: 'msg1',
          senderId: 'user1',
          text: 'Test',
          timestamp: timestamp,
          read: false,
        );

        final updated = original.copyWith(read: true, delivered: true);

        expect(updated.read, true);
        expect(updated.delivered, true);
        expect(updated.id, original.id);
        expect(updated.senderId, original.senderId);
        expect(updated.text, original.text);
        expect(updated.timestamp, original.timestamp);
        expect(updated.type, original.type);
      });

      test('mantiene read si no se pasa parámetro', () {
        final original = Message(
          id: 'msg1',
          senderId: 'user1',
          text: 'Test',
          timestamp: timestamp,
          read: true,
        );

        final copy = original.copyWith();
        expect(copy.read, true);
      });
    });
  });
}
