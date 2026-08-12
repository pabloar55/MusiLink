import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/friend_request.dart';

void main() {
  group('FriendRequest', () {
    final now = DateTime(2025, 6, 15, 10, 0);

    group('constructor', () {
      test('crea FriendRequest con todos los campos', () {
        final request = FriendRequest(
          id: 'req1',
          senderId: 'user1',
          receiverId: 'user2',
          status: FriendRequestStatus.pending,
          createdAt: now,
          updatedAt: now,
        );

        expect(request.id, 'req1');
        expect(request.senderId, 'user1');
        expect(request.receiverId, 'user2');
        expect(request.status, FriendRequestStatus.pending);
      });
    });

    group('toFirestore', () {
      test('serializa correctamente con status pending', () {
        final request = FriendRequest(
          id: 'req1',
          senderId: 'user1',
          receiverId: 'user2',
          status: FriendRequestStatus.pending,
          createdAt: now,
          updatedAt: now,
        );

        final map = request.toFirestore();

        expect(map['senderId'], 'user1');
        expect(map['receiverId'], 'user2');
        expect(map['status'], 'pending');
        expect(map.containsKey('id'), false);
      });
    });
  });

  group('FriendRequestStatus', () {
    test('solo contiene solicitudes pendientes', () {
      expect(FriendRequestStatus.values, [FriendRequestStatus.pending]);
    });
  });
}
