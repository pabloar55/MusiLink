import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/relationship.dart';

void main() {
  group('RelationshipResult', () {
    test('solo permite interactuar en el chat cuando son amigos', () {
      expect(
        const RelationshipResult(RelationshipStatus.friends).canInteractInChat,
        isTrue,
      );

      for (final status in [
        RelationshipStatus.none,
        RelationshipStatus.requestSent,
        RelationshipStatus.requestReceived,
        RelationshipStatus.blocked,
      ]) {
        expect(
          RelationshipResult(status).canInteractInChat,
          isFalse,
          reason: '$status no debe permitir escribir ni reaccionar',
        );
      }
    });
  });

  group('resolveRelationship', () {
    RelationshipResult resolve({
      List<String> blocked = const [],
      List<String> friends = const [],
      String? sent,
      String? received,
    }) => resolveRelationship(
      'other',
      privateUserData: {'blockedUsers': blocked, 'friends': friends},
      sentRequestId: sent,
      receivedRequestId: received,
    );

    void expectRelationship(
      RelationshipResult result,
      RelationshipStatus status, [
      String? requestId,
    ]) {
      expect(result.status, status);
      expect(result.requestId, requestId);
    }

    test('el bloqueo prevalece sobre la amistad y las solicitudes', () {
      expectRelationship(
        resolve(
          blocked: ['other'],
          friends: ['other'],
          sent: 'me_other',
          received: 'other_me',
        ),
        RelationshipStatus.blocked,
      );
    });

    test('la amistad prevalece sobre las solicitudes', () {
      expectRelationship(
        resolve(friends: ['other'], sent: 'me_other', received: 'other_me'),
        RelationshipStatus.friends,
      );
    });

    test('la solicitud enviada prevalece sobre la recibida', () {
      expectRelationship(
        resolve(sent: 'me_other', received: 'other_me'),
        RelationshipStatus.requestSent,
        'me_other',
      );
      expectRelationship(
        resolve(received: 'other_me'),
        RelationshipStatus.requestReceived,
        'other_me',
      );
    });

    test('solo cuentan las listas que contienen a ese usuario', () {
      expectRelationship(
        resolve(blocked: ['someone'], friends: ['someone_else']),
        RelationshipStatus.none,
      );
    });

    test('sin perfil privado no hay relación', () {
      expectRelationship(
        resolveRelationship('other', privateUserData: null),
        RelationshipStatus.none,
      );
    });
  });
}
