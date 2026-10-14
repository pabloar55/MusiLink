import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef ChatNotificationEntry = ({
  String senderName,
  String? senderId,
  String text,
  DateTime sentAt,
});

/// Últimos mensajes de cada chat con los que Android agrupa sus avisos en un
/// único MessagingStyle. Se guardan en SharedPreferences porque los avisos
/// también se componen desde el isolate de segundo plano.
class ChatNotificationHistory {
  ChatNotificationHistory(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'chat_notification_history';
  static const maxMessagesPerChat = 5;

  /// Añade [entry] al chat y devuelve sus mensajes recientes, del más antiguo
  /// al más nuevo, conservando como máximo [maxMessagesPerChat].
  Future<List<ChatNotificationEntry>> append(
    String chatId,
    ChatNotificationEntry entry,
  ) async {
    final history = _read() ?? <String, dynamic>{};
    final messages = (history[chatId] as List<dynamic>? ?? <dynamic>[])
        .map((item) => Map<String, Object>.from(item as Map))
        .toList();
    messages.add({
      'senderName': entry.senderName,
      'senderId': ?entry.senderId,
      'text': entry.text,
      'timestamp': entry.sentAt.millisecondsSinceEpoch,
    });
    if (messages.length > maxMessagesPerChat) {
      messages.removeRange(0, messages.length - maxMessagesPerChat);
    }
    history[chatId] = messages;
    await _prefs.setString(_key, jsonEncode(history));
    return messages.map(_decode).toList();
  }

  /// Olvida los mensajes de [chatId] cuando se retiran sus avisos.
  Future<void> remove(String chatId) async {
    final history = _read();
    if (history == null) return;
    history.remove(chatId);
    await _prefs.setString(_key, jsonEncode(history));
  }

  /// Olvida los mensajes de todos los chats al terminar la sesión.
  Future<void> clear() => _prefs.remove(_key);

  Map<String, dynamic>? _read() {
    final raw = _prefs.getString(_key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  static ChatNotificationEntry _decode(Map<String, Object> message) => (
    senderName: message['senderName']! as String,
    senderId: message['senderId'] as String?,
    text: message['text']! as String,
    sentAt: DateTime.fromMillisecondsSinceEpoch(message['timestamp']! as int),
  );
}
