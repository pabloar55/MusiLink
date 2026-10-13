import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/services/service_exceptions.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';

/// Servicio para crear y administrar chats de grupo. Los mensajes y el
/// historial de la conversación siguen en ChatService.
class GroupChatService with AuthenticatedService {
  GroupChatService({
    required this._firestore,
    required this._auth,
    required this._functions,
    this._onGroupLeft,
  });

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Avisa de que el usuario `uid` ha salido del grupo `chatId`.
  final void Function(String uid, String chatId)? _onGroupLeft;

  @override
  FirebaseAuth get auth => _auth;
  late final CollectionReference<Map<String, dynamic>> _chatsRef = _firestore
      .collection(FirestoreCollections.chats);

  static const maxGroupParticipants = 20;

  String newGroupChatId() => _chatsRef.doc().id;

  Future<Chat> createGroupChat({
    required String chatId,
    required String name,
    required List<String> participantIds,
  }) async {
    try {
      final data = {
        'chatId': chatId,
        'name': name.trim(),
        'participantIds': participantIds,
      };
      await _functions
          .httpsCallable('createGroupChat')
          .call<void>(data)
          .timeout(const Duration(seconds: 30));
      return Chat.fromFirestore(
        await _chatsRef.doc(chatId).get().timeout(const Duration(seconds: 10)),
      );
    } catch (error, stack) {
      reportError(error, stack).ignore();
      Error.throwWithStackTrace(toServiceException(error), stack);
    }
  }

  /// El backend exige que cada persona añadida sea amiga mutua de quien llama
  /// y que no tenga bloqueos con los miembros actuales.
  Future<void> addGroupMembers(
    String chatId,
    List<String> participantIds,
  ) async {
    try {
      await _functions
          .httpsCallable('addGroupChatMembers')
          .call<void>({'chatId': chatId, 'participantIds': participantIds})
          .timeout(const Duration(seconds: 30));
    } catch (error, stack) {
      reportError(error, stack).ignore();
      Error.throwWithStackTrace(toServiceException(error), stack);
    }
  }

  /// La pertenencia solo la modifica el backend, que además limpia los datos
  /// por miembro y elimina el grupo cuando se queda vacío.
  Future<void> leaveGroupChat(String chatId) async {
    final uid = currentUid;
    try {
      await _functions
          .httpsCallable('leaveGroupChat')
          .call<void>({'chatId': chatId})
          .timeout(const Duration(seconds: 30));
      _onGroupLeft?.call(uid, chatId);
    } catch (error, stack) {
      reportError(error, stack).ignore();
      rethrow;
    }
  }

  /// [photoUrl] debe ser la URL de descarga de la foto subida para el grupo.
  Future<void> updateGroupPhoto(String chatId, String photoUrl) async {
    try {
      await _chatsRef.doc(chatId).update({'photoUrl': photoUrl});
    } catch (error, stack) {
      reportError(error, stack).ignore();
      rethrow;
    }
  }

  /// The boundary comes from confirmed messages actually displayed on screen.
  /// A concurrent newer summary is left unread until the next message snapshot.
  Future<void> markGroupMessagesAsRead(String chatId, DateTime through) async {
    final uid = currentUid;
    final readAt = Timestamp.fromDate(through);
    try {
      final chatRef = _chatsRef.doc(chatId);
      await _firestore.runTransaction((tx) async {
        final doc = await tx.get(chatRef);
        final data = doc.data();
        if (data == null || data['type'] != 'group') return;
        final latest = data['lastMessageTime'] as Timestamp?;
        final previous = (data['lastReadAt'] as Map?)?[uid] as Timestamp?;
        if ((latest != null && latest.compareTo(readAt) > 0) ||
            (previous != null && previous.compareTo(readAt) >= 0)) {
          return;
        }
        tx.update(chatRef, {'lastReadAt.$uid': readAt, 'unreadCounts.$uid': 0});
      });
    } catch (error, stack) {
      await reportError(error, stack);
    }
  }
}
