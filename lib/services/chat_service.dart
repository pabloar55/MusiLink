import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/utils/firestore_collections.dart';

/// Servicio para gestionar chats y mensajes en Firestore.
class ChatService with AuthenticatedService {
  ChatService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  FirebaseAuth get auth => _auth;
  late final CollectionReference<Map<String, dynamic>> _chatsRef = _firestore
      .collection(FirestoreCollections.chats);
  late final CollectionReference<Map<String, dynamic>> _privateUsersRef =
      _firestore.collection(FirestoreCollections.userPrivate);
  late final CollectionReference<Map<String, dynamic>> _rateLimitsRef =
      _firestore.collection(FirestoreCollections.rateLimits);

  // Cache por otherUid: evita re-query al abrir el mismo chat varias veces.
  final Map<String, Chat> _chatByOtherUid = {};

  /// Limpia la caché en memoria. Llamar al hacer logout.
  void clearCache() => _chatByOtherUid.clear();

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
          tx.set(docRef, {
            'participants': [currentUid, otherUid],
            'lastMessage': '',
            'lastMessageTime': Timestamp.fromDate(now),
            'createdAt': Timestamp.fromDate(now),
            'unreadCounts': {currentUid: 0, otherUid: 0},
          });
          chat = Chat(
            id: docRef.id,
            participants: [currentUid, otherUid],
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
  /// Los chats borrados suavemente (deletedAt[uid] >= lastMessageTime) quedan ocultos.
  Stream<List<Chat>> getChats() {
    return _chatsRef
        .where('participants', arrayContains: currentUid)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .handleError((e, st) => reportError(e, st).ignore())
        .map(
          (snapshot) => snapshot.docs.map(Chat.fromFirestore).where((chat) {
            final dt = chat.deletedAt[currentUid];
            return dt == null || chat.lastMessageTime.isAfter(dt);
          }).toList(),
        );
  }

  static const int _deleteBatchSize = 499;

  /// Devuelve el timestamp de borrado suave del usuario actual para un chat,
  /// o null si no ha borrado el chat (incluye chats recién creados).
  /// Lanza si Firestore falla — el llamador debe decidir cómo recuperarse.
  Future<DateTime?> getDeletedSince(String chatId) async {
    try {
      final snap = await _chatsRef.doc(chatId).get();
      if (!snap.exists) return null;
      return Chat.fromFirestore(snap).deletedAt[currentUid];
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Borrado suave del chat para el usuario actual (estilo WhatsApp).
  ///
  /// Escribe deletedAt[currentUid] = ahora. El chat desaparece de la lista
  /// hasta que el otro participante envie un nuevo mensaje.
  /// La limpieza fisica del chat, cuando corresponda, la hace Cloud Functions
  /// con Admin SDK. El cliente no intenta borrar mensajes ajenos ni el chat.
  Future<void> softDeleteChat(String chatId) async {
    try {
      final chatRef = _chatsRef.doc(chatId);

      await chatRef.update({
        'deletedAt.$currentUid': FieldValue.serverTimestamp(),
      });

      _chatByOtherUid.removeWhere((_, c) => c.id == chatId);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Elimina un chat y todos sus mensajes.
  ///
  /// Se conserva solo para compatibilidad interna/tests y clientes antiguos.
  /// Los flujos nuevos deben usar [softDeleteChat]; el backend hace la
  /// limpieza definitiva cuando sea seguro.
  Future<void> deleteChat(String chatId) async {
    try {
      final messagesRef = _chatsRef
          .doc(chatId)
          .collection(FirestoreCollections.messages);

      // Paginar el borrado para no superar el límite de 500 ops por batch.
      while (true) {
        final snapshot = await messagesRef.limit(_deleteBatchSize).get();
        if (snapshot.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        if (snapshot.docs.length < _deleteBatchSize) break;
      }

      await _chatsRef.doc(chatId).delete();
      _chatByOtherUid.removeWhere((_, chat) => chat.id == chatId);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Borra del historial todos los datos aportados por [uid].
  ///
  /// Se conservan los mensajes de la otra persona para no destruir su copia de
  /// la conversación. Si tras borrar los mensajes del usuario el chat queda
  /// vacío, se elimina el documento del chat completo.
  Future<void> deleteAllUserChatData(String uid) async {
    try {
      final chats = await _chatsRef
          .where('participants', arrayContains: uid)
          .get();

      for (final chatDoc in chats.docs) {
        await _deleteUserDataFromChat(chatDoc.reference, uid);
      }
      _chatByOtherUid.removeWhere((_, chat) => chat.participants.contains(uid));
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  Future<void> _deleteUserDataFromChat(
    DocumentReference<Map<String, dynamic>> chatRef,
    String uid,
  ) async {
    final messagesRef = chatRef.collection(FirestoreCollections.messages);

    await _deleteMessagesSentBy(messagesRef, uid);
    await _removeUserReactions(messagesRef, uid);
    await _refreshOrDeleteChat(chatRef, messagesRef, uid);
  }

  Future<void> _deleteMessagesSentBy(
    CollectionReference<Map<String, dynamic>> messagesRef,
    String uid,
  ) async {
    while (true) {
      final snapshot = await messagesRef
          .where('senderId', isEqualTo: uid)
          .limit(_deleteBatchSize)
          .get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < _deleteBatchSize) break;
    }
  }

  Future<void> _removeUserReactions(
    CollectionReference<Map<String, dynamic>> messagesRef,
    String uid,
  ) async {
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      var query = messagesRef
          .orderBy(FieldPath.documentId)
          .limit(_deleteBatchSize);
      if (cursor != null) query = query.startAfterDocument(cursor);

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;
      cursor = snapshot.docs.last;

      final batch = _firestore.batch();
      var hasUpdates = false;

      for (final doc in snapshot.docs) {
        final reactions = Map<String, dynamic>.from(
          doc.data()['reactions'] as Map? ?? const {},
        );
        if (reactions.isEmpty) continue;

        var changed = false;
        final scrubbed = <String, List<String>>{};
        for (final entry in reactions.entries) {
          final users = List<String>.from(entry.value as List? ?? const []);
          final filtered = users.where((userId) => userId != uid).toList();
          if (filtered.length != users.length) changed = true;
          if (filtered.isNotEmpty) scrubbed[entry.key] = filtered;
        }

        if (changed) {
          hasUpdates = true;
          batch.update(doc.reference, {'reactions': scrubbed});
        }
      }

      if (hasUpdates) await batch.commit();
      if (snapshot.docs.length < _deleteBatchSize) break;
    }
  }

  Future<void> _refreshOrDeleteChat(
    DocumentReference<Map<String, dynamic>> chatRef,
    CollectionReference<Map<String, dynamic>> messagesRef,
    String deletedUid,
  ) async {
    final latestSnapshot = await messagesRef
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (latestSnapshot.docs.isEmpty) return;

    final latest = latestSnapshot.docs.first.data();
    await chatRef.update({
      'lastMessage': (latest['text'] ?? '').toString(),
      'lastMessageTime':
          latest['timestamp'] as Timestamp? ?? FieldValue.serverTimestamp(),
      'unreadCounts.$deletedUid': FieldValue.delete(),
    });
  }

  //  Mensajes

  /// Envía un mensaje de texto en un chat.
  static const int maxMessageBytes = 2000;
  static const Duration _messageRateLimitWindow = Duration(seconds: 10);

  static bool _isValidMessageText(String text) =>
      text.isNotEmpty && utf8.encode(text).length <= maxMessageBytes;

  Map<String, Object?> _nextMessageRateLimit(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final data = snap.data() ?? const <String, dynamic>{};
    final windowStart = data['messageWindowStart'] as Timestamp?;
    final count = (data['messageCount'] as int?) ?? 0;
    final shouldReset =
        windowStart == null ||
        DateTime.now().difference(windowStart.toDate()) >
            _messageRateLimitWindow;

    return {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'messageWindowStart': shouldReset
          ? FieldValue.serverTimestamp()
          : windowStart,
      'messageCount': shouldReset ? 1 : count + 1,
    };
  }

  Future<void> sendMessage(
    String chatId,
    String text, {
    required String otherUid,
  }) async {
    final trimmed = text.trim();
    if (!_isValidMessageText(trimmed)) {
      throw ArgumentError('Invalid message');
    }
    await _throwIfBlockedByMe(otherUid);

    try {
      final now = DateTime.now();
      final message = Message(
        id: '',
        senderId: currentUid,
        text: trimmed,
        timestamp: now,
      );

      final chatRef = _chatsRef.doc(chatId);
      final msgRef = chatRef.collection(FirestoreCollections.messages).doc();
      final limiterRef = _rateLimitsRef.doc(currentUid);

      await _firestore.runTransaction((tx) async {
        final limiterSnap = await tx.get(limiterRef);

        // Añadir el mensaje a la subcolección
        tx.set(msgRef, {
          ...message.toFirestore(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Actualizar último mensaje e incrementar el contador del destinatario
        tx.update(chatRef, {
          'lastMessage': trimmed,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCounts.$otherUid': FieldValue.increment(1),
        });
        tx.set(
          limiterRef,
          _nextMessageRateLimit(limiterSnap),
          SetOptions(merge: true),
        );
      });
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  static const int messagesPageSize = 30;

  /// Stream de los últimos [messagesPageSize] mensajes de un chat, en tiempo real.
  /// Los resultados se devuelven ordenados cronológicamente (ascendente).
  /// Si [since] no es null, solo se devuelven mensajes posteriores a ese timestamp.
  Stream<List<Message>> getMessages(String chatId, {DateTime? since}) {
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

    return query
        .limit(messagesPageSize)
        .snapshots()
        .handleError((e, st) => reportError(e, st).ignore())
        .map(
          (snapshot) => snapshot.docs.reversed
              .map(Message.fromFirestore)
              .whereType<Message>()
              .toList(),
        );
  }

  /// Carga mensajes anteriores a [before] para paginación inversa.
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
  Future<void> sendTrackMessage(
    String chatId,
    Track track, {
    required String otherUid,
  }) async {
    final text = '${track.title} - ${track.artist}'.trim();
    if (!_isValidMessageText(text)) {
      throw ArgumentError('Invalid message');
    }
    await _throwIfBlockedByMe(otherUid);

    try {
      final now = DateTime.now();
      final message = Message(
        id: '',
        senderId: currentUid,
        text: text,
        timestamp: now,
        type: MessageType.track,
        trackData: track,
      );

      final chatRef = _chatsRef.doc(chatId);
      final msgRef = chatRef.collection(FirestoreCollections.messages).doc();
      final limiterRef = _rateLimitsRef.doc(currentUid);

      await _firestore.runTransaction((tx) async {
        final limiterSnap = await tx.get(limiterRef);

        tx.set(msgRef, {
          ...message.toFirestore(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        tx.update(chatRef, {
          'lastMessage': '🎵 ${track.title}',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCounts.$otherUid': FieldValue.increment(1),
        });
        tx.set(
          limiterRef,
          _nextMessageRateLimit(limiterSnap),
          SetOptions(merge: true),
        );
      });
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
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
