/// Estado de la relación entre el usuario actual y otro usuario.
enum RelationshipStatus { none, requestSent, requestReceived, friends, blocked }

/// Resultado de consultar la relación con otro usuario.
class RelationshipResult {
  final RelationshipStatus status;
  final String? requestId; // ID del friend_request si existe
  const RelationshipResult(this.status, [this.requestId]);

  bool get canInteractInChat => status == RelationshipStatus.friends;
}

/// Relación con [otherUid] según el perfil privado del usuario actual
/// ([privateUserData]) y las solicitudes pendientes en cada dirección. Un
/// bloqueo prevalece sobre la amistad, la amistad sobre cualquier solicitud y
/// la solicitud enviada sobre la recibida.
RelationshipResult resolveRelationship(
  String otherUid, {
  required Map<String, dynamic>? privateUserData,
  String? sentRequestId,
  String? receivedRequestId,
}) {
  final blocked = privateUserData?['blockedUsers'] as List? ?? const [];
  if (blocked.contains(otherUid)) {
    return const RelationshipResult(RelationshipStatus.blocked);
  }
  final friends = privateUserData?['friends'] as List? ?? const [];
  if (friends.contains(otherUid)) {
    return const RelationshipResult(RelationshipStatus.friends);
  }
  if (sentRequestId != null) {
    return RelationshipResult(RelationshipStatus.requestSent, sentRequestId);
  }
  if (receivedRequestId != null) {
    return RelationshipResult(
      RelationshipStatus.requestReceived,
      receivedRequestId,
    );
  }
  return const RelationshipResult(RelationshipStatus.none);
}
