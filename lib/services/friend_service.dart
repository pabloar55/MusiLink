import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/models/friend_request.dart';
import 'package:musi_link/utils/firestore_collections.dart';

/// Estado de la relación entre el usuario actual y otro usuario.
enum RelationshipStatus { none, requestSent, requestReceived, friends, blocked }

/// Resultado de consultar la relación con otro usuario.
class RelationshipResult {
  final RelationshipStatus status;
  final String? requestId; // ID del friend_request si existe
  const RelationshipResult(this.status, [this.requestId]);

  bool get canInteractInChat => status == RelationshipStatus.friends;
}

/// Servicio para gestionar solicitudes de amistad y amigos en Firestore.
class FriendService with AuthenticatedService {
  FriendService({
    required this._firestore,
    required this._auth,
    required this._functions,
  });

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  FirebaseAuth get auth => _auth;
  late final CollectionReference<Map<String, dynamic>> _requestsRef = _firestore
      .collection(FirestoreCollections.friendRequests);
  late final CollectionReference<Map<String, dynamic>> _privateUsersRef =
      _firestore.collection(FirestoreCollections.userPrivate);
  // ─── Solicitudes ────────────────────────────────────────

  /// Envía una solicitud de amistad a [receiverUid].
  Future<void> sendRequest(String receiverUid) async {
    if (receiverUid == currentUid) return;
    try {
      final callable = _functions.httpsCallable('sendFriendRequest');
      await callable.call<void>({'receiverId': receiverUid});
    } catch (e, stack) {
      if (!isRateLimitError(e)) await reportError(e, stack);
      rethrow;
    }
  }

  /// Acepta una solicitud de amistad.
  /// La callable valida que el usuario actual sea el receptor y crea ambos
  /// lados de la amistad mediante una transacción privilegiada.
  Future<void> acceptRequest(String requestId, String otherUid) async {
    try {
      final callable = _functions.httpsCallable('acceptFriendRequest');
      await callable.call<void>({'requestId': requestId, 'senderId': otherUid});
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Rechaza una solicitud de amistad.
  Future<void> rejectRequest(String requestId) async {
    try {
      await _requestsRef.doc(requestId).delete();
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Cancela (elimina) una solicitud de amistad enviada.
  Future<void> cancelRequest(String requestId) async {
    try {
      await _firestore.runTransaction((tx) async {
        final docRef = _requestsRef.doc(requestId);
        final snapshot = await tx.get(docRef);
        if (!snapshot.exists ||
            snapshot.data()?['senderId'] != currentUid ||
            snapshot.data()?['status'] != FriendRequestStatus.pending.name) {
          return;
        }
        tx.delete(docRef);
      });
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  // ─── Streams ────────────────────────────────────────────

  /// Stream de solicitudes de amistad recibidas pendientes.
  Stream<List<FriendRequest>> getReceivedRequests() {
    return _requestsRef
        .where('receiverId', isEqualTo: currentUid)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((e, st) => reportError(e, st).ignore())
        .map(
          (snapshot) => snapshot.docs.map(FriendRequest.fromFirestore).toList(),
        );
  }

  /// Stream de solicitudes de amistad enviadas pendientes.
  Stream<List<FriendRequest>> getSentRequests() {
    return _requestsRef
        .where('senderId', isEqualTo: currentUid)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .handleError((e, st) => reportError(e, st).ignore())
        .map(
          (snapshot) => snapshot.docs.map(FriendRequest.fromFirestore).toList(),
        );
  }

  /// Stream de la lista de amigos del usuario actual.
  Stream<List<String>> getFriendsStream() {
    return _privateUsersRef
        .doc(currentUid)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return <String>[];
          final data = doc.data();
          if (data == null) return <String>[];
          return List<String>.from(data['friends'] as List? ?? []);
        })
        .distinct((a, b) => a.length == b.length && a.toSet().containsAll(b));
  }

  /// Obtiene la lista privada de amigos del usuario actual.
  Future<List<String>> getFriends({bool serverOnly = false}) async {
    try {
      final docRef = _privateUsersRef.doc(currentUid);
      final doc = serverOnly
          ? await docRef.get(const GetOptions(source: Source.server))
          : await docRef.get();
      if (!doc.exists) return const <String>[];
      return List<String>.from(doc.data()?['friends'] as List? ?? []);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  // ─── Consultas ──────────────────────────────────────────

  /// Comprueba si el usuario actual es amigo de [otherUid].
  Future<bool> areFriends(String otherUid) async {
    try {
      final doc = await _privateUsersRef.doc(currentUid).get();
      if (!doc.exists) return false;
      final friends = List<String>.from(doc.data()?['friends'] as List? ?? []);
      return friends.contains(otherUid);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Obtiene en bloque el estado de la relación con cada UID de [otherUids].
  ///
  /// Lee una sola vez el perfil privado actual y agrupa las solicitudes en
  /// consultas `in`, evitando las tres lecturas por usuario de
  /// [getRelationship].
  Future<Map<String, RelationshipResult>> getRelationships(
    Iterable<String> otherUids,
  ) async {
    final authenticatedUid = currentUid;
    final uids = otherUids
        .where((uid) => uid.isNotEmpty && uid != authenticatedUid)
        .toSet()
        .toList(growable: false);
    if (uids.isEmpty) return const <String, RelationshipResult>{};

    try {
      const whereInLimit = 30;
      final chunks = <List<String>>[];
      for (var i = 0; i < uids.length; i += whereInLimit) {
        chunks.add(uids.sublist(i, (i + whereInLimit).clamp(0, uids.length)));
      }

      final privateUserFuture = _privateUsersRef.doc(authenticatedUid).get();
      final sentFuture = Future.wait(
        chunks.map(
          (chunk) => _requestsRef
              .where('senderId', isEqualTo: authenticatedUid)
              .where('receiverId', whereIn: chunk)
              .where('status', isEqualTo: FriendRequestStatus.pending.name)
              .get(),
        ),
      );
      final receivedFuture = Future.wait(
        chunks.map(
          (chunk) => _requestsRef
              .where('receiverId', isEqualTo: authenticatedUid)
              .where('senderId', whereIn: chunk)
              .where('status', isEqualTo: FriendRequestStatus.pending.name)
              .get(),
        ),
      );

      final results = await Future.wait<Object>([
        privateUserFuture,
        sentFuture,
        receivedFuture,
      ]);
      final privateUser = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final sentSnapshots =
          results[1] as List<QuerySnapshot<Map<String, dynamic>>>;
      final receivedSnapshots =
          results[2] as List<QuerySnapshot<Map<String, dynamic>>>;

      final privateData = privateUser.data() ?? const <String, dynamic>{};
      final blocked = Set<String>.from(
        privateData['blockedUsers'] as List? ?? const [],
      );
      final friends = Set<String>.from(
        privateData['friends'] as List? ?? const [],
      );
      final sentByUid = <String, String>{};
      for (final snapshot in sentSnapshots) {
        for (final doc in snapshot.docs) {
          final receiverId = doc.data()['receiverId'];
          if (receiverId is String) sentByUid[receiverId] = doc.id;
        }
      }
      final receivedByUid = <String, String>{};
      for (final snapshot in receivedSnapshots) {
        for (final doc in snapshot.docs) {
          final senderId = doc.data()['senderId'];
          if (senderId is String) receivedByUid[senderId] = doc.id;
        }
      }

      return {
        for (final uid in uids)
          uid: blocked.contains(uid)
              ? const RelationshipResult(RelationshipStatus.blocked)
              : friends.contains(uid)
              ? const RelationshipResult(RelationshipStatus.friends)
              : sentByUid.containsKey(uid)
              ? RelationshipResult(
                  RelationshipStatus.requestSent,
                  sentByUid[uid],
                )
              : receivedByUid.containsKey(uid)
              ? RelationshipResult(
                  RelationshipStatus.requestReceived,
                  receivedByUid[uid],
                )
              : const RelationshipResult(RelationshipStatus.none),
      };
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Obtiene el estado de la relación con [otherUid].
  Future<RelationshipResult> getRelationship(String otherUid) async {
    try {
      final results = await Future.wait([
        _privateUsersRef.doc(currentUid).get(),
        _requestsRef
            .where('senderId', isEqualTo: currentUid)
            .where('receiverId', isEqualTo: otherUid)
            .where('status', isEqualTo: FriendRequestStatus.pending.name)
            .limit(1)
            .get(),
        _requestsRef
            .where('senderId', isEqualTo: otherUid)
            .where('receiverId', isEqualTo: currentUid)
            .where('status', isEqualTo: FriendRequestStatus.pending.name)
            .limit(1)
            .get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final sent = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final received = results[2] as QuerySnapshot<Map<String, dynamic>>;

      final data = userDoc.data() ?? {};
      final blocked = List<String>.from(data['blockedUsers'] as List? ?? []);
      if (blocked.contains(otherUid)) {
        return const RelationshipResult(RelationshipStatus.blocked);
      }
      final friends = List<String>.from(data['friends'] as List? ?? []);
      if (friends.contains(otherUid)) {
        return const RelationshipResult(RelationshipStatus.friends);
      }
      if (sent.docs.isNotEmpty) {
        return RelationshipResult(
          RelationshipStatus.requestSent,
          sent.docs.first.id,
        );
      }
      if (received.docs.isNotEmpty) {
        return RelationshipResult(
          RelationshipStatus.requestReceived,
          received.docs.first.id,
        );
      }

      return const RelationshipResult(RelationshipStatus.none);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Escucha en tiempo real la relacin con [otherUid].
  Stream<RelationshipResult> watchRelationship(String otherUid) {
    late final StreamController<RelationshipResult> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    DocumentSnapshot<Map<String, dynamic>>? userDoc;
    DocumentSnapshot<Map<String, dynamic>>? sentDoc;
    DocumentSnapshot<Map<String, dynamic>>? receivedDoc;

    RelationshipResult relationshipFromSnapshots() {
      final data = userDoc?.data() ?? {};
      final blocked = List<String>.from(data['blockedUsers'] as List? ?? []);
      if (blocked.contains(otherUid)) {
        return const RelationshipResult(RelationshipStatus.blocked);
      }
      final friends = List<String>.from(data['friends'] as List? ?? []);
      if (friends.contains(otherUid)) {
        return const RelationshipResult(RelationshipStatus.friends);
      }

      if (sentDoc?.data()?['status'] == FriendRequestStatus.pending.name) {
        return RelationshipResult(RelationshipStatus.requestSent, sentDoc!.id);
      }

      if (receivedDoc?.data()?['status'] == FriendRequestStatus.pending.name) {
        return RelationshipResult(
          RelationshipStatus.requestReceived,
          receivedDoc!.id,
        );
      }

      return const RelationshipResult(RelationshipStatus.none);
    }

    void emitRelationship() {
      if (!controller.isClosed) controller.add(relationshipFromSnapshots());
    }

    void handleRelationshipStreamError(Object error, StackTrace stack) {
      if (isNetworkError(error)) {
        if (userDoc == null && sentDoc == null && receivedDoc == null) {
          emitRelationship();
        }
        return;
      }

      unawaited(reportError(error, stack));
      if (!controller.isClosed) controller.addError(error, stack);
    }

    controller = StreamController<RelationshipResult>(
      onListen: () {
        subscriptions.add(
          _privateUsersRef.doc(currentUid).snapshots().listen((snapshot) {
            userDoc = snapshot;
            emitRelationship();
          }, onError: handleRelationshipStreamError),
        );
        subscriptions.add(
          _requestsRef.doc('${currentUid}_$otherUid').snapshots().listen((
            snapshot,
          ) {
            sentDoc = snapshot;
            emitRelationship();
          }, onError: handleRelationshipStreamError),
        );
        subscriptions.add(
          _requestsRef.doc('${otherUid}_$currentUid').snapshots().listen((
            snapshot,
          ) {
            receivedDoc = snapshot;
            emitRelationship();
          }, onError: handleRelationshipStreamError),
        );
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream.distinct(
      (a, b) => a.status == b.status && a.requestId == b.requestId,
    );
  }

  // ─── Eliminar cuenta ────────────────────────────────────

  /// Elimina todos los datos de amistad de [uid]:
  /// lo quita del array `friends` de sus amigos y borra todas sus solicitudes.
  Future<void> deleteAllUserFriendData(String uid) async {
    try {
      // Quitar uid del array friends de cada amigo suyo
      final userDoc = await _privateUsersRef.doc(uid).get();
      final friends = List<String>.from(
        userDoc.data()?['friends'] as List? ?? [],
      );
      const batchSize = 400;
      for (var i = 0; i < friends.length; i += batchSize) {
        final chunk = friends.sublist(
          i,
          (i + batchSize).clamp(0, friends.length),
        );
        final batch = _firestore.batch();
        for (final friendUid in chunk) {
          batch.update(_privateUsersRef.doc(friendUid), {
            'friends': FieldValue.arrayRemove([uid]),
          });
        }
        await batch.commit();
      }

      // Eliminar todas las solicitudes de amistad (enviadas y recibidas)
      final sent = await _requestsRef.where('senderId', isEqualTo: uid).get();
      final received = await _requestsRef
          .where('receiverId', isEqualTo: uid)
          .get();
      final allDocs = [...sent.docs, ...received.docs];
      const requestBatchSize = 400;
      for (var i = 0; i < allDocs.length; i += requestBatchSize) {
        final chunk = allDocs.sublist(
          i,
          (i + requestBatchSize).clamp(0, allDocs.length),
        );
        final batch = _firestore.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  // ─── Bloquear usuarios ──────────────────────────────────

  /// Bloquea a [otherUid]: lo añade a `blockedUsers`, elimina la amistad
  /// y borra las solicitudes pendientes en ambas direcciones.
  Future<void> blockUser(String otherUid) async {
    if (otherUid == currentUid) return;
    try {
      final currentUserRef = _privateUsersRef.doc(currentUid);
      final otherUserRef = _privateUsersRef.doc(otherUid);
      final directRequestRef = _requestsRef.doc('${currentUid}_$otherUid');
      final inverseRequestRef = _requestsRef.doc('${otherUid}_$currentUid');

      await _firestore.runTransaction((tx) async {
        final currentUserSnap = await tx.get(currentUserRef);
        final directRequest = await tx.get(directRequestRef);
        final inverseRequest = await tx.get(inverseRequestRef);
        final currentFriends = List<String>.from(
          currentUserSnap.data()?['friends'] as List? ?? const [],
        );

        tx.set(currentUserRef, {
          'blockedUsers': FieldValue.arrayUnion([otherUid]),
          'friends': FieldValue.arrayRemove([otherUid]),
        }, SetOptions(merge: true));
        if (currentFriends.contains(otherUid)) {
          tx.update(otherUserRef, {
            'friends': FieldValue.arrayRemove([currentUid]),
          });
        }
        if (directRequest.exists) tx.delete(directRequestRef);
        if (inverseRequest.exists) tx.delete(inverseRequestRef);
      });
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Desbloquea a [otherUid].
  Future<void> unblockUser(String otherUid) async {
    try {
      await _privateUsersRef.doc(currentUid).update({
        'blockedUsers': FieldValue.arrayRemove([otherUid]),
      });
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Devuelve la lista de UIDs bloqueados por el usuario actual.
  Future<List<String>> getBlockedUsers() async {
    try {
      final doc = await _privateUsersRef.doc(currentUid).get();
      if (!doc.exists) return const <String>[];
      return List<String>.from(doc.data()?['blockedUsers'] as List? ?? []);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Stream en tiempo real de los UIDs bloqueados por el usuario actual.
  Stream<List<String>> getBlockedUsersStream() {
    return _privateUsersRef
        .doc(currentUid)
        .snapshots()
        .handleError((e, st) => reportError(e, st).ignore())
        .map((doc) {
          if (!doc.exists) return <String>[];
          return List<String>.from(doc.data()?['blockedUsers'] as List? ?? []);
        });
  }

  // ─── Eliminar amigo ─────────────────────────────────────

  /// Elimina a [otherUid] de la lista de amigos de ambos.
  Future<void> removeFriend(String otherUid) async {
    try {
      final currentUserRef = _privateUsersRef.doc(currentUid);
      final otherUserRef = _privateUsersRef.doc(otherUid);
      final directRequestRef = _requestsRef.doc('${currentUid}_$otherUid');
      final inverseRequestRef = _requestsRef.doc('${otherUid}_$currentUid');

      await _firestore.runTransaction((tx) async {
        final directRequest = await tx.get(directRequestRef);
        final inverseRequest = await tx.get(inverseRequestRef);

        tx.update(currentUserRef, {
          'friends': FieldValue.arrayRemove([otherUid]),
        });
        tx.update(otherUserRef, {
          'friends': FieldValue.arrayRemove([currentUid]),
        });
        if (directRequest.exists) tx.delete(directRequestRef);
        if (inverseRequest.exists) tx.delete(inverseRequestRef);
      });
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }
}
