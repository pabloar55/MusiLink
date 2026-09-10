import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/services/chat_message_cache.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/utils/firestore_collections.dart';

/// Servicio para gestionar chats y mensajes en Firestore.
class ChatService with AuthenticatedService {
  ChatService({
    required this._firestore,
    required this._auth,
    required this._functions,
    this._messageCache,
  });

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final ChatMessageCache? _messageCache;

  @override
  FirebaseAuth get auth => _auth;
  late final CollectionReference<Map<String, dynamic>> _chatsRef = _firestore
      .collection(FirestoreCollections.chats);
  late final CollectionReference<Map<String, dynamic>> _privateUsersRef =
      _firestore.collection(FirestoreCollections.userPrivate);
  // Cache por otherUid: evita re-query al abrir el mismo chat varias veces.
  final Map<String, Chat> _chatByOtherUid = {};
  // Solo la última página de los 20 chats más recientes, separada por usuario.
  final Map<(String, String), CachedChatMessages> _recentMessages = {};
  final Map<(String, String), ({DateTime? since, Future<void> future})>
  _prefetchingMessages = {};
  final Map<(String, String), Object> _messageCacheTokens = {};

  final Map<(String, String), Map<String, Message>> _outgoing = {};
  final _outgoingChanges = StreamController<(String, String)>.broadcast();
  final Map<(String, String), Future<void>> _deliveryRequests = {};
  final Set<(String, String)> _deliveryRefreshes = {};

  List<Message> _withOutgoing(
    String uid,
    String chatId,
    List<Message> messages,
  ) {
    final ids = messages.map((message) => message.id).toSet();
    return [
      ...messages,
      ...?_outgoing[(uid, chatId)]?.values.where(
        (message) => !ids.contains(message.id),
      ),
    ];
  }

  Object _messageCacheToken(String uid, String chatId) =>
      _messageCacheTokens.putIfAbsent((uid, chatId), Object.new);

  /// Historial y filtro de borrado disponibles antes del primer snapshot.
  /// null significa que aún no se ha cargado; messages vacío es un chat vacío.
  CachedChatMessages? getCachedHistory(String chatId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final cached =
        _recentMessages[(uid, chatId)] ?? _messageCache?.read(uid, chatId);
    if (cached != null) _recentMessages[(uid, chatId)] = cached;
    return cached;
  }

  List<Message>? getCachedMessages(String chatId) =>
      getCachedHistory(chatId)?.messages;

  void _invalidateMessages(String uid, String chatId) {
    _recentMessages.remove((uid, chatId));
    _prefetchingMessages.remove((uid, chatId));
    _messageCacheTokens.remove((uid, chatId));
    _messageCache?.remove(uid, chatId);
  }

  void _checkDeletedSince(String uid, String chatId, DateTime? since) {
    final cached =
        _recentMessages[(uid, chatId)] ?? _messageCache?.read(uid, chatId);
    final pending = _prefetchingMessages[(uid, chatId)];
    if ((cached != null && cached.since != since) ||
        (pending != null && pending.since != since)) {
      _invalidateMessages(uid, chatId);
    }
  }

  /// Limpia las vistas de arranque en memoria y disco al hacer logout.
  void clearCache() {
    for (final key in _outgoing.keys.toList()) {
      _outgoing.remove(key);
      _outgoingChanges.add(key);
    }
    _chatByOtherUid.clear();
    _recentMessages.clear();
    _prefetchingMessages.clear();
    _messageCacheTokens.clear();
    _messageCache?.clear();
  }

  // ─── Chats ────────────────────────────────────────────────

  /// Returns a deterministic, content-addressed document ID for a chat between
  /// two users: the two UIDs joined by "_", sorted lexicographically so that
  /// _chatId(a, b) == _chatId(b, a) for any pair.
  static String _chatId(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> _throwIfBlockedByMe(String otherUid) async {
    final doc = await _privateUsersRef.doc(currentUid).get();
    final blockedUsers = List<String>.from(
      doc.data()?['blockedUsers'] as List? ?? const [],
    );
    if (blockedUsers.contains(otherUid)) {
      throw StateError('Cannot interact with a blocked user.');
    }
  }

  /// Crea un chat entre el usuario actual y [otherUid].
  /// Si ya existe un chat entre ambos, devuelve el existente.
  ///
  /// Usa un ID determinista (UIDs ordenados) y una transacción Firestore para
  /// garantizar idempotencia: si dos clientes llaman a este método al mismo
  /// tiempo, la transacción del segundo verá el documento ya creado y no
  /// generará un duplicado.
  Future<Chat> getOrCreateChat(String otherUid) async {
    await _throwIfBlockedByMe(otherUid);

    final cached = _chatByOtherUid[otherUid];
    if (cached != null) return cached;

    try {
      final docRef = _chatsRef.doc(_chatId(currentUid, otherUid));

      late Chat chat;
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (snap.exists) {
          chat = Chat.fromFirestore(snap);
        } else {
          final now = DateTime.now();
          final participants = [currentUid, otherUid]..sort();
          tx.set(docRef, {
            'participants': participants,
            'lastMessage': '',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'unreadCounts': {currentUid: 0, otherUid: 0},
          });
          chat = Chat(
            id: docRef.id,
            participants: participants,
            lastMessageTime: now,
            createdAt: now,
          );
        }
      });

      _chatByOtherUid[otherUid] = chat;
      return chat;
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Stream de los chats del usuario actual, ordenados por último mensaje.
  /// Los chats sin mensajes y los borrados suavemente
  /// (deletedAt[uid] >= lastMessageTime) quedan ocultos.
  Stream<List<Chat>> getChats() {
    final uid = currentUid;
    return _chatsRef
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .handleError((e, st) => reportError(e, st).ignore())
        .map((snapshot) {
          final chats = snapshot.docs.map(Chat.fromFirestore).where((chat) {
            final dt = chat.deletedAt[uid];
            _checkDeletedSince(uid, chat.id, dt);
            if (chat.lastMessage.isEmpty) return false;
            return dt == null || chat.lastMessageTime.isAfter(dt);
          }).toList();
          // MainScreen escucha esta lista para el contador de pendientes:
          // adelantar la carga incluso antes de entrar en la pestaña de chats.
          if (_auth.currentUser?.uid == uid) {
            for (final chat in chats) {
              if ((chat.unreadCounts[uid] ?? 0) > 0) {
                unawaited(markMessagesAsDelivered(chat.id));
              }
            }
            for (final chat in chats.take(6)) {
              unawaited(prefetchMessages(chat));
            }
          }
          return chats;
        });
  }

  /// Precarga una sola página usando el filtro de borrado de la lista de chats.
  /// No bloquea la navegación ni mantiene listeners adicionales abiertos.
  Future<void> prefetchMessages(Chat chat, {bool refresh = false}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || !chat.participants.contains(uid)) return;
    final since = chat.deletedAt[uid];
    _checkDeletedSince(uid, chat.id, since);
    if (chat.lastMessage.isEmpty ||
        (since != null && !chat.lastMessageTime.isAfter(since))) {
      return;
    }
    final key = (uid, chat.id);
    if (getCachedHistory(chat.id) != null && !refresh) return;
    final pending = _prefetchingMessages[key];
    if (pending != null) return pending.future;

    final future = _prefetchMessages(chat.id, uid, since);
    _prefetchingMessages[key] = (since: since, future: future);
    try {
      await future;
    } finally {
      if (identical(_prefetchingMessages[key]?.future, future)) {
        _prefetchingMessages.remove(key);
      }
    }
  }

  Future<void> _prefetchMessages(
    String chatId,
    String uid,
    DateTime? since,
  ) async {
    final token = _messageCacheToken(uid, chatId);
    final previous = _recentMessages[(uid, chatId)];
    try {
      final snapshot = await _messagesQuery(chatId, since: since).get();
      // Un resultado tardío no debe reemplazar una actualización del chat abierto.
      if (!identical(token, _messageCacheTokens[(uid, chatId)]) ||
          _auth.currentUser?.uid != uid ||
          _recentMessages[(uid, chatId)] != previous) {
        return;
      }
      _cacheMessages(uid, chatId, since, _decodeMessages(snapshot));
    } catch (error, stack) {
      // La pantalla conserva su carga normal si falla esta optimización.
      reportError(error, stack).ignore();
    }
  }

  /// Usa únicamente datos locales para preparar el primer fotograma del chat.
  /// Verifica participantes y filtro de borrado antes de restaurar mensajes.
  Future<void> restoreLocalHistory(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final token = _messageCacheToken(uid, chatId);
    final previous = _recentMessages[(uid, chatId)];
    try {
      final doc = await _chatsRef
          .doc(chatId)
          .get(const GetOptions(source: Source.cache));
      if (!doc.exists) return;
      final chat = Chat.fromFirestore(doc);
      if (!chat.participants.contains(uid)) return;
      final since = chat.deletedAt[uid];
      final snapshot = await _messagesQuery(
        chatId,
        since: since,
      ).get(const GetOptions(source: Source.cache));
      if (_auth.currentUser?.uid != uid ||
          !identical(token, _messageCacheTokens[(uid, chatId)]) ||
          _recentMessages[(uid, chatId)] != previous) {
        return;
      }
      _checkDeletedSince(uid, chatId, since);
      final messages = _decodeMessages(snapshot);
      // Una consulta local vacía también puede significar que nunca se descargó.
      if (messages.isNotEmpty) _cacheMessages(uid, chatId, since, messages);
    } catch (_) {
      // Sin caché Firestore, se conserva la vista persistida o la carga normal.
    }
  }

  /// La notificación identifica el chat; los mensajes se obtienen de Firestore,
  /// conservando IDs, canciones, reacciones y el límite de historial borrado.
  Future<void> prepareNotificationChat(Map<String, dynamic> data) async {
    final uid = _auth.currentUser?.uid;
    final chatId = data['chatId'];
    if (data['type'] != 'new_message' ||
        uid == null ||
        chatId is! String ||
        chatId.isEmpty ||
        (data['recipientId'] != null && data['recipientId'] != uid)) {
      return;
    }
    final token = _messageCacheToken(uid, chatId);
    try {
      final doc = await _chatsRef
          .doc(chatId)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!doc.exists ||
          _auth.currentUser?.uid != uid ||
          !identical(token, _messageCacheTokens[(uid, chatId)])) {
        return;
      }
      final chat = Chat.fromFirestore(doc);
      if (!chat.participants.contains(uid)) return;
      await markMessagesAsDelivered(chatId);
      await prefetchMessages(
        chat,
        refresh: true,
      ).timeout(const Duration(seconds: 5));
    } catch (error, stack) {
      reportError(error, stack).ignore();
    }
  }

  List<Message> _decodeMessages(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs.reversed
          .map(Message.fromFirestore)
          .whereType<Message>()
          .toList();

  void _cacheMessages(
    String uid,
    String chatId,
    DateTime? since,
    List<Message> messages,
  ) {
    final key = (uid, chatId);
    _recentMessages.remove(key);
    _recentMessages[key] = (
      since: since,
      messages: List<Message>.unmodifiable(
        messages.skip(
          messages.length > messagesPageSize
              ? messages.length - messagesPageSize
              : 0,
        ),
      ),
    );
    if (_recentMessages.length > 20) {
      _recentMessages.remove(_recentMessages.keys.first);
    }
    _messageCache?.write(uid, chatId, _recentMessages[key]!);
  }

  static const int _deleteBatchSize = 499;

  /// Devuelve el timestamp de borrado suave del usuario actual para un chat,
  /// o null si no ha borrado el chat (incluye chats recién creados).
  /// Lanza si Firestore falla — el llamador debe decidir cómo recuperarse.
  Future<DateTime?> getDeletedSince(String chatId) async {
    final uid = currentUid;
    try {
      final snap = await _chatsRef.doc(chatId).get();
      final since = snap.exists
          ? Chat.fromFirestore(snap).deletedAt[uid]
          : null;
      _checkDeletedSince(uid, chatId, since);
      return since;
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Borrado suave del chat para el usuario actual (estilo WhatsApp).
  ///
  /// Escribe deletedAt[currentUid] = ahora y pone a cero su contador pendiente.
  /// El chat desaparece de la lista hasta que el otro participante envie un
  /// nuevo mensaje.
  /// La limpieza fisica del chat, cuando corresponda, la hace Cloud Functions
  /// con Admin SDK. El cliente no intenta borrar mensajes ajenos ni el chat.
  Future<void> softDeleteChat(String chatId) async {
    final uid = currentUid;
    _invalidateMessages(uid, chatId);
    try {
      final chatRef = _chatsRef.doc(chatId);

      await chatRef.update({
        'deletedAt.$uid': FieldValue.serverTimestamp(),
        'unreadCounts.$uid': 0,
      });

      _invalidateMessages(uid, chatId);
      _chatByOtherUid.removeWhere((_, c) => c.id == chatId);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  //  Mensajes

  /// Envía un mensaje de texto en un chat.
  static const int maxMessageBytes = 2000;

  static bool _isValidMessageText(String text) =>
      text.isNotEmpty && utf8.encode(text).length <= maxMessageBytes;

  Future<void> sendMessage(String chatId, String text) async {
    final trimmed = text.trim();
    if (!_isValidMessageText(trimmed)) {
      throw ArgumentError('Invalid message');
    }

    await _sendOutgoing(chatId, trimmed);
  }

  Future<void> _sendOutgoing(String chatId, String text, {Track? track}) async {
    final uid = currentUid;
    final key = (uid, chatId);
    final messageId = _chatsRef
        .doc(chatId)
        .collection(FirestoreCollections.messages)
        .doc()
        .id;
    final pending = _outgoing.putIfAbsent(key, () => {});
    pending[messageId] = Message(
      id: messageId,
      senderId: uid,
      text: text,
      timestamp: DateTime.now(),
      type: track == null ? MessageType.text : MessageType.track,
      trackData: track,
      isPending: true,
    );
    _outgoingChanges.add(key);
    try {
      await _functions.httpsCallable('sendChatMessage').call<void>({
        'chatId': chatId,
        'messageId': messageId,
        'type': track == null ? 'text' : 'track',
        if (track == null) 'text': text else 'trackData': track.toMap(),
      });
      // Se conserva hasta que el listener confirma el mismo ID, incluso si la
      // respuesta de la callable llega antes que el snapshot.
    } catch (e, stack) {
      // Un snapshot confirmado prevalece sobre un error tardío de transporte.
      if (!pending.containsKey(messageId)) return;
      pending.remove(messageId);
      _outgoingChanges.add(key);
      if (!isRateLimitError(e)) await reportError(e, stack);
      rethrow;
    }
  }

  static const int messagesPageSize = 30;

  /// Stream de mensajes de un chat en tiempo real. Sin [from], devuelve los
  /// últimos [messagesPageSize]; con [from], escucha todo el historial cargado
  /// desde ese timestamp (incluido), además de los mensajes nuevos.
  /// Los resultados se devuelven ordenados cronológicamente (ascendente).
  /// Si [since] no es null, solo se devuelven mensajes posteriores a ese timestamp.
  Stream<List<Message>> getMessages(
    String chatId, {
    DateTime? since,
    DateTime? from,
  }) {
    final uid = currentUid;
    final token = _messageCacheToken(uid, chatId);
    return Stream<List<Message>>.multi((controller) {
      var latest = getCachedMessages(chatId) ?? <Message>[];
      void emit() => controller.add(_withOutgoing(uid, chatId, latest));
      final outgoing = _outgoingChanges.stream.listen((key) {
        if (key == (uid, chatId)) emit();
      });
      if (_outgoing[(uid, chatId)]?.isNotEmpty ?? false) emit();
      final remote = _messagesQuery(chatId, since: since, from: from)
          .snapshots()
          .listen(
            (snapshot) {
              latest = _decodeMessages(snapshot);
              final pending = _outgoing[(uid, chatId)];
              for (final message in latest) {
                pending?.remove(message.id);
              }
              if (identical(token, _messageCacheTokens[(uid, chatId)]) &&
                  _auth.currentUser?.uid == uid) {
                _cacheMessages(uid, chatId, since, latest);
                unawaited(_acknowledgeMessages(uid, snapshot.docs));
              }
              emit();
            },
            onError: (Object error, StackTrace stack) {
              reportError(error, stack).ignore();
              controller.addError(error, stack);
            },
            onDone: controller.close,
          );
      controller.onCancel = () async {
        await outgoing.cancel();
        await remote.cancel();
      };
    });
  }

  /// La recepción no implica lectura ni cambia el contador de no leídos.
  /// Reutiliza el índice read/senderId y admite mensajes antiguos sin delivered.
  Future<void> markMessagesAsDelivered(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final key = (uid, chatId);
    final pending = _deliveryRequests[key];
    if (pending != null) {
      _deliveryRefreshes.add(key);
      return pending;
    }
    final future = () async {
      do {
        _deliveryRefreshes.remove(key);
        await _receiveUnreadMessages(uid, chatId);
      } while (_deliveryRefreshes.remove(key) && _auth.currentUser?.uid == uid);
    }();
    _deliveryRequests[key] = future;
    try {
      await future;
    } finally {
      if (identical(_deliveryRequests[key], future)) {
        final _ = _deliveryRequests.remove(key);
      }
    }
  }

  Future<void> _receiveUnreadMessages(String uid, String chatId) async {
    try {
      final query = _chatsRef
          .doc(chatId)
          .collection(FirestoreCollections.messages)
          .where('read', isEqualTo: false)
          .where('senderId', isNotEqualTo: uid)
          .limit(_deleteBatchSize);
      QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
      while (_auth.currentUser?.uid == uid) {
        final snapshot =
            await (cursor == null ? query : query.startAfterDocument(cursor))
                .get();
        await _acknowledgeMessages(uid, snapshot.docs);
        if (snapshot.docs.length < _deleteBatchSize) break;
        cursor = snapshot.docs.last;
      }
    } catch (error, stack) {
      reportError(error, stack).ignore();
    }
  }

  Future<void> _acknowledgeMessages(
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_auth.currentUser?.uid != uid) return;
    final incoming = docs.where((doc) {
      final data = doc.data();
      return data['senderId'] != uid &&
          data['delivered'] != true &&
          data['read'] != true;
    }).toList();
    try {
      for (
        var offset = 0;
        offset < incoming.length;
        offset += _deleteBatchSize
      ) {
        if (_auth.currentUser?.uid != uid) return;
        final batch = _firestore.batch();
        for (final doc in incoming.skip(offset).take(_deleteBatchSize)) {
          batch.update(doc.reference, {'delivered': true});
        }
        await batch.commit();
      }
    } catch (error, stack) {
      reportError(error, stack).ignore();
    }
  }

  Query<Map<String, dynamic>> _messagesQuery(
    String chatId, {
    DateTime? since,
    DateTime? from,
  }) {
    var query = _chatsRef
        .doc(chatId)
        .collection(FirestoreCollections.messages)
        .orderBy('timestamp', descending: true);

    if (since != null) {
      query = query.where(
        'timestamp',
        isGreaterThan: Timestamp.fromDate(since),
      );
    }

    return from == null
        ? query.limit(messagesPageSize)
        : query.endAt([Timestamp.fromDate(from)]);
  }

  /// Localiza la siguiente página anterior a [before]. El llamador debe ampliar
  /// [getMessages] con su primer timestamp para mantenerla actualizada.
  /// Devuelve hasta [messagesPageSize] mensajes en orden cronológico ascendente.
  /// Si [since] no es null, no carga mensajes anteriores a ese timestamp.
  Future<List<Message>> loadOlderMessages(
    String chatId, {
    required DateTime before,
    DateTime? since,
  }) async {
    try {
      var query = _chatsRef
          .doc(chatId)
          .collection(FirestoreCollections.messages)
          .where('timestamp', isLessThan: Timestamp.fromDate(before))
          .orderBy('timestamp', descending: true);

      if (since != null) {
        query = query.where(
          'timestamp',
          isGreaterThan: Timestamp.fromDate(since),
        );
      }

      final snapshot = await query.limit(messagesPageSize).get();

      return snapshot.docs.reversed
          .map(Message.fromFirestore)
          .whereType<Message>()
          .toList();
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Marca todos los mensajes no leídos del otro usuario como leídos y
  /// resetea el contador desnormalizado del usuario actual en el documento
  /// del chat.
  Future<void> markMessagesAsRead(String chatId) async {
    try {
      // Marcar mensajes individuales como leídos (impulsa los ticks de lectura).
      final messagesRef = _chatsRef
          .doc(chatId)
          .collection(FirestoreCollections.messages)
          .where('read', isEqualTo: false)
          .where('senderId', isNotEqualTo: currentUid)
          .limit(_deleteBatchSize);

      while (true) {
        final snapshot = await messagesRef.get();
        if (snapshot.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {'read': true});
        }
        await batch.commit();

        if (snapshot.docs.length < _deleteBatchSize) break;
      }

      // Resetear el contador desnormalizado al final. Si el proceso se
      // interrumpe antes, la siguiente lectura del chat puede reintentar y
      // completar los ticks pendientes antes de limpiar el badge.
      await _chatsRef.doc(chatId).update({'unreadCounts.$currentUid': 0});
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return;
      await reportError(e, StackTrace.current);
    } catch (e, stack) {
      await reportError(e, stack);
    }
  }

  /// Envía una canción como mensaje en un chat.
  Future<void> sendTrackMessage(String chatId, Track track) async {
    final text = '${track.title} - ${track.artist}'.trim();
    if (!_isValidMessageText(text)) {
      throw ArgumentError('Invalid message');
    }

    await _sendOutgoing(chatId, text, track: track);
  }

  /// Añade o quita una reacción del usuario actual en un mensaje.
  /// Usa una transacción para evitar race conditions cuando varios
  /// usuarios reaccionan al mismo mensaje simultáneamente.
  Future<void> toggleReaction(
    String chatId,
    String messageId,
    String emoji,
  ) async {
    try {
      final msgRef = _chatsRef
          .doc(chatId)
          .collection(FirestoreCollections.messages)
          .doc(messageId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(msgRef);
        if (!doc.exists) return;

        final data = doc.data()!;
        final reactions = Map<String, dynamic>.from(
          data['reactions'] as Map? ?? {},
        );

        // Remove any existing reaction from this user on a different emoji
        for (final key in reactions.keys.toList()) {
          if (key != emoji) {
            final list = List<String>.from(reactions[key] as List? ?? []);
            if (list.remove(currentUid)) {
              if (list.isEmpty) {
                reactions.remove(key);
              } else {
                reactions[key] = list;
              }
            }
          }
        }

        final users = List<String>.from(reactions[emoji] as List? ?? []);

        if (users.contains(currentUid)) {
          users.remove(currentUid);
        } else {
          users.add(currentUid);
        }

        if (users.isEmpty) {
          reactions.remove(emoji);
        } else {
          reactions[emoji] = users;
        }

        transaction.update(msgRef, {'reactions': reactions});
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return;
      await reportError(e, StackTrace.current);
    } catch (e, stack) {
      await reportError(e, stack);
    }
  }
}
