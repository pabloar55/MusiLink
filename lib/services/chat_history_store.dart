import 'package:musi_link/models/message.dart';
import 'package:musi_link/services/chat_message_cache.dart';

/// Última página de los chats recientes, en memoria y respaldada en disco,
/// separada por usuario. Decide además si una carga tardía sigue siendo válida.
class ChatHistoryStore {
  ChatHistoryStore(this._disk, {required this._maxMessages});

  static const maxChats = 20;

  final ChatMessageCache? _disk;
  final int _maxMessages;
  final Map<(String, String), CachedChatMessages> _recent = {};
  final Map<(String, String), ({DateTime? since, Future<void> future})>
  _prefetching = {};
  final Map<(String, String), Object> _tokens = {};

  /// Marca de validez del chat: cambia cuando su historial se invalida.
  Object token(String uid, String chatId) =>
      _tokens.putIfAbsent((uid, chatId), Object.new);

  bool isCurrent(String uid, String chatId, Object token) =>
      identical(token, _tokens[(uid, chatId)]);

  /// Lo que hay en memoria, sin consultar el disco.
  CachedChatMessages? inMemory(String uid, String chatId) =>
      _recent[(uid, chatId)];

  /// Historial guardado, o null si aún no se ha cargado.
  CachedChatMessages? read(String uid, String chatId) {
    final cached = _recent[(uid, chatId)] ?? _disk?.read(uid, chatId);
    if (cached != null) _recent[(uid, chatId)] = cached;
    return cached;
  }

  void write(
    String uid,
    String chatId,
    DateTime? since,
    List<Message> messages,
  ) {
    final key = (uid, chatId);
    _recent.remove(key);
    _recent[key] = (
      since: since,
      messages: List<Message>.unmodifiable(
        messages.skip(
          messages.length > _maxMessages ? messages.length - _maxMessages : 0,
        ),
      ),
    );
    if (_recent.length > maxChats) {
      _recent.remove(_recent.keys.first);
    }
    _disk?.write(uid, chatId, _recent[key]!);
  }

  void invalidate(String uid, String chatId) {
    _recent.remove((uid, chatId));
    _prefetching.remove((uid, chatId));
    _tokens.remove((uid, chatId));
    _disk?.remove(uid, chatId);
  }

  /// Invalida el historial si se guardó o se está cargando con otro filtro
  /// de borrado.
  void invalidateIfSinceChanged(String uid, String chatId, DateTime? since) {
    final cached = _recent[(uid, chatId)] ?? _disk?.read(uid, chatId);
    final pending = _prefetching[(uid, chatId)];
    if ((cached != null && cached.since != since) ||
        (pending != null && pending.since != since)) {
      invalidate(uid, chatId);
    }
  }

  /// Ejecuta [load] salvo que ya haya una precarga en curso para el chat, en
  /// cuyo caso espera a esa.
  Future<void> prefetch(
    String uid,
    String chatId,
    DateTime? since,
    Future<void> Function() load,
  ) async {
    final key = (uid, chatId);
    final pending = _prefetching[key];
    if (pending != null) return pending.future;

    final future = load();
    _prefetching[key] = (since: since, future: future);
    try {
      await future;
    } finally {
      if (identical(_prefetching[key]?.future, future)) {
        _prefetching.remove(key);
      }
    }
  }

  void clear() {
    _recent.clear();
    _prefetching.clear();
    _tokens.clear();
    _disk?.clear();
  }
}
