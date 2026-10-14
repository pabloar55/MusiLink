String? notificationLocationFromData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  switch (type) {
    case 'new_message':
      final chatId = data['chatId']?.toString();
      if (chatId != null && data['chatType'] == 'group') {
        return '/group-chat/${Uri.encodeComponent(chatId)}';
      }
      final otherUserId = data['otherUserId']?.toString();
      final otherUserName = data['otherUserName']?.toString();
      if (chatId == null || otherUserId == null) return '/?tab=messages';

      return Uri(
        path: '/chat',
        queryParameters: {
          'chatId': chatId,
          'otherUserId': otherUserId,
          if (otherUserName != null && otherUserName.trim().isNotEmpty)
            'otherUserName': otherUserName,
        },
      ).toString();
    case 'friend_request':
    case 'friend_request_accepted':
      return '/?tab=friends';
    case 'daily_song_expired':
    case 'daily_song_liked':
    case 'friend_digest':
      return '/?tab=daily-song';
  }
  return null;
}

/// Ruta con la que arranca la app: la de la notificación que la abrió o, en
/// web, la que trae el hash de la URL ([webFragment]).
String? launchLocation({String? notificationLocation, String? webFragment}) {
  if (notificationLocation != null) return notificationLocation;
  if (webFragment != null && webFragment.startsWith('/')) return webFragment;
  return null;
}

/// Chat individual cuyo historial local conviene restaurar antes de mostrar
/// [location], o null si no es la ruta de un chat individual.
String? directChatIdOf(String? location) {
  final route = location == null ? null : Uri.tryParse(location);
  return route?.path == '/chat' ? route?.queryParameters['chatId'] : null;
}

enum NotificationNavigation {
  /// La conversación ya está abierta: no se navega.
  stay,

  /// Se apila sobre la pantalla actual para poder volver a ella.
  push,

  /// Sustituye la pila.
  go,
}

/// Cómo abrir [target], el destino de una notificación, estando en
/// [current]. Las conversaciones se apilan salvo que ya estén abiertas; el
/// resto de destinos sustituyen la pila.
NotificationNavigation notificationNavigation({
  required Uri current,
  required Uri target,
}) {
  if (target.path == '/chat') {
    final sameChat =
        current.path == '/chat' &&
        current.queryParameters['chatId'] == target.queryParameters['chatId'];
    return sameChat ? NotificationNavigation.stay : NotificationNavigation.push;
  }
  if (target.path.startsWith('/group-chat/')) {
    return current.path == target.path
        ? NotificationNavigation.stay
        : NotificationNavigation.push;
  }
  return NotificationNavigation.go;
}
