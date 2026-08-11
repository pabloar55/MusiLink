/// Nombres de las colecciones (y subcolecciones) de Firestore.
///
/// Usar estas constantes en lugar de literales de cadena elimina el riesgo
/// de typos silenciosos que no se detectan en compilación ni en runtime
/// hasta que una operación falla.
abstract final class FirestoreCollections {
  static const String users = 'users';
  static const String usernames = 'usernames';
  static const String userPrivate = 'user_private';
  static const String pushTokens = 'push_tokens';
  static const String recommendations = 'recommendations';
  static const String chats = 'chats';
  static const String messages = 'messages';
  static const String friendRequests = 'friend_requests';
  static const String rateLimits = 'rate_limits';
  static const String accountDeletions = 'account_deletions';
}
