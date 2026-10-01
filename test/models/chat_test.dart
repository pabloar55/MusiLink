import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/chat.dart';

void main() {
  group('Chat', () {
    final now = DateTime(2025, 6, 15, 10, 0);

    group('constructor', () {
      test('crea Chat con todos los campos', () {
        final chat = Chat(
          id: 'chat1',
          participants: ['user1', 'user2'],
          lastMessage: 'Hola!',
          lastMessageTime: now,
          createdAt: now,
          unreadCounts: {'user1': 3, 'user2': 0},
        );

        expect(chat.id, 'chat1');
        expect(chat.participants, ['user1', 'user2']);
        expect(chat.lastMessage, 'Hola!');
        expect(chat.lastMessageTime, now);
        expect(chat.createdAt, now);
        expect(chat.unreadCounts['user1'], 3);
        expect(chat.unreadCounts['user2'], 0);
      });

      test('lastMessage tiene valor por defecto vacío', () {
        final chat = Chat(
          id: 'chat1',
          participants: ['user1', 'user2'],
          lastMessageTime: now,
          createdAt: now,
        );

        expect(chat.lastMessage, '');
      });

      test('unreadCounts tiene valor por defecto vacío', () {
        final chat = Chat(
          id: 'chat1',
          participants: ['user1', 'user2'],
          lastMessageTime: now,
          createdAt: now,
        );

        expect(chat.unreadCounts, isEmpty);
      });
    });

    group('toFirestore', () {
      test('serializa correctamente', () {
        final chat = Chat(
          id: 'chat1',
          participants: ['user1', 'user2'],
          lastMessage: 'Hola!',
          lastMessageTime: now,
          createdAt: now,
          unreadCounts: {'user1': 2, 'user2': 0},
        );

        final map = chat.toFirestore();

        expect(map['participants'], ['user1', 'user2']);
        expect(map['lastMessage'], 'Hola!');
        expect(map['unreadCounts'], {'user1': 2, 'user2': 0});
        expect(map.containsKey('id'), false);
      });
    });

    group('copyWith', () {
      test('actualiza lastMessage y lastMessageTime', () {
        final original = Chat(
          id: 'chat1',
          participants: ['user1', 'user2'],
          lastMessage: 'Hola!',
          lastMessageTime: now,
          createdAt: now,
          unreadCounts: {'user1': 1},
        );

        final newTime = DateTime(2025, 6, 15, 12, 0);
        final updated = original.copyWith(
          lastMessage: 'Adiós!',
          lastMessageTime: newTime,
        );

        expect(updated.lastMessage, 'Adiós!');
        expect(updated.lastMessageTime, newTime);
        expect(updated.id, original.id);
        expect(updated.participants, original.participants);
        expect(updated.createdAt, original.createdAt);
        expect(updated.unreadCounts, original.unreadCounts);
      });

      test('mantiene valores si no se pasan parámetros', () {
        final original = Chat(
          id: 'chat1',
          participants: ['user1', 'user2'],
          lastMessage: 'Test',
          lastMessageTime: now,
          createdAt: now,
        );

        final copy = original.copyWith();

        expect(copy.lastMessage, original.lastMessage);
        expect(copy.lastMessageTime, original.lastMessageTime);
      });

      test('conserva la foto del grupo', () {
        final group = Chat(
          id: 'group1',
          isGroup: true,
          name: 'Grupo',
          photoUrl: 'https://example.com/group.jpg',
          participants: ['user1', 'user2', 'user3'],
          lastMessageTime: now,
          createdAt: now,
        );

        expect(group.copyWith(lastMessage: 'Hola').photoUrl, group.photoUrl);
        expect(group.toFirestore()['photoUrl'], group.photoUrl);
      });
    });
  });
}
