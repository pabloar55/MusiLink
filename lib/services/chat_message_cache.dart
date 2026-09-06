import 'dart:convert';

import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CachedChatMessages = ({DateTime? since, List<Message> messages});

/// Vista de arranque acotada. Solo el isolate de la interfaz escribe aquí;
/// la precarga en background utiliza la persistencia propia de Firestore.
class ChatMessageCache {
  ChatMessageCache(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'chat_messages_v1.';
  static const maxChats = 20;
  static const maxMessages = 30;
  final Map<(String, String), CachedChatMessages?> _entries = {};

  String _userPrefix(String uid) =>
      '$_prefix${base64Url.encode(utf8.encode(uid))}.';
  String _key(String uid, String chatId) =>
      '${_userPrefix(uid)}chat.${Uri.encodeComponent(chatId)}';
  String _indexKey(String uid) => '${_userPrefix(uid)}index';

  CachedChatMessages? read(String uid, String chatId) => _entries.putIfAbsent(
    (uid, chatId),
    () {
      try {
        final raw = _prefs.getString(_key(uid, chatId));
        if (raw == null) return null;
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        final since = entry['since'] as int?;
        final cutoff = since == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(since);
        final messages = (entry['messages'] as List)
            .map((value) {
              final item = value as Map<String, dynamic>;
              return Message(
                id: item['id'] as String,
                senderId: item['senderId'] as String,
                text: item['text'] as String,
                timestamp: DateTime.fromMicrosecondsSinceEpoch(
                  item['timestamp'] as int,
                ),
                read: item['read'] as bool,
                type: MessageType.values.byName(item['type'] as String),
                trackData: item['trackData'] == null
                    ? null
                    : Track.fromMap(item['trackData'] as Map<String, dynamic>),
                reactions: (item['reactions'] as Map<String, dynamic>).map(
                  (emoji, users) =>
                      MapEntry(emoji, List<String>.from(users as List)),
                ),
              );
            })
            .where(
              (message) => cutoff == null || message.timestamp.isAfter(cutoff),
            )
            .toList();
        return (since: cutoff, messages: List<Message>.unmodifiable(messages));
      } catch (_) {
        // Una caché antigua o dañada nunca impide abrir la aplicación.
        _prefs.remove(_key(uid, chatId)).ignore();
        return null;
      }
    },
  );

  void write(String uid, String chatId, CachedChatMessages entry) {
    final visible = entry.messages
        .where(
          (message) =>
              entry.since == null || message.timestamp.isAfter(entry.since!),
        )
        .toList();
    final cached = (
      since: entry.since,
      messages: List<Message>.unmodifiable(
        visible.skip(
          visible.length > maxMessages ? visible.length - maxMessages : 0,
        ),
      ),
    );
    _entries[(uid, chatId)] = cached;
    final index = List<String>.of(_prefs.getStringList(_indexKey(uid)) ?? [])
      ..remove(chatId)
      ..add(chatId);
    while (index.length > maxChats) {
      final oldest = index.removeAt(0);
      _entries.remove((uid, oldest));
      _prefs.remove(_key(uid, oldest)).ignore();
    }
    _prefs.setStringList(_indexKey(uid), index).ignore();
    _save(uid, chatId, cached);
  }

  void remove(String uid, String chatId) {
    _entries.remove((uid, chatId));
    _prefs.remove(_key(uid, chatId)).ignore();
    final index = List<String>.of(_prefs.getStringList(_indexKey(uid)) ?? []);
    if (index.remove(chatId)) {
      _prefs.setStringList(_indexKey(uid), index).ignore();
    }
  }

  void clear() {
    _entries.clear();
    for (final key in _prefs.getKeys().where(
      (key) => key.startsWith(_prefix),
    )) {
      _prefs.remove(key).ignore();
    }
  }

  void _save(String uid, String chatId, CachedChatMessages entry) {
    final data = {
      'since': entry.since?.microsecondsSinceEpoch,
      'messages': entry.messages
          .map(
            (message) => {
              'id': message.id,
              'senderId': message.senderId,
              'text': message.text,
              'timestamp': message.timestamp.microsecondsSinceEpoch,
              'read': message.read,
              'type': message.type.name,
              'trackData': message.trackData?.toMap(),
              'reactions': message.reactions,
            },
          )
          .toList(),
    };
    _prefs.setString(_key(uid, chatId), jsonEncode(data)).ignore();
  }
}
