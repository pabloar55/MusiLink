import 'dart:async';

import 'package:musi_link/models/message.dart';

/// Mensajes enviados que el backend aún no ha confirmado, por usuario y chat.
class PendingMessages {
  final Map<(String, String), Map<String, Message>> _pending = {};
  final _changes = StreamController<(String, String)>.broadcast();

  /// Emite la clave (uid, chatId) cuyos pendientes han cambiado.
  Stream<(String, String)> get changes => _changes.stream;

  bool hasAny(String uid, String chatId) =>
      _pending[(uid, chatId)]?.isNotEmpty ?? false;

  /// Añade a [messages] los pendientes que aún no figuran entre ellos.
  List<Message> merge(String uid, String chatId, List<Message> messages) {
    final ids = messages.map((message) => message.id).toSet();
    return [
      ...messages,
      ...?_pending[(uid, chatId)]?.values.where(
        (message) => !ids.contains(message.id),
      ),
    ];
  }

  /// Registra [message] y devuelve cómo retirarlo si el envío falla. Esa
  /// función devuelve false cuando el backend ya lo había confirmado.
  bool Function() add(String uid, String chatId, Message message) {
    final key = (uid, chatId);
    final pending = _pending.putIfAbsent(key, () => {});
    pending[message.id] = message;
    _changes.add(key);
    return () {
      if (!pending.containsKey(message.id)) return false;
      pending.remove(message.id);
      _changes.add(key);
      return true;
    };
  }

  /// Retira los pendientes que ya aparecen en [confirmed].
  void confirm(String uid, String chatId, Iterable<Message> confirmed) {
    final pending = _pending[(uid, chatId)];
    if (pending == null) return;
    for (final message in confirmed) {
      pending.remove(message.id);
    }
  }

  void clear() {
    for (final key in _pending.keys.toList()) {
      _pending.remove(key);
      _changes.add(key);
    }
  }
}
