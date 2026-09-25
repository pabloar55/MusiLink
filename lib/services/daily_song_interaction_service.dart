import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';

typedef DailySongPublication = ({String ownerId, DateTime publishedAt});

class DailySongInteractionService with AuthenticatedService {
  DailySongInteractionService({required this._firestore, required this._auth});

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  FirebaseAuth get auth => _auth;

  CollectionReference<Map<String, dynamic>> _likes(String ownerId) => _firestore
      .collection(FirestoreCollections.users)
      .doc(ownerId)
      .collection(FirestoreCollections.dailySongLikes);

  Stream<Set<String>> watchLikes(DailySongPublication publication) =>
      _likes(publication.ownerId)
          .where(
            'publishedAt',
            isEqualTo: Timestamp.fromDate(publication.publishedAt),
          )
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet())
          .handleError((Object error, StackTrace stack) {
            reportError(error, stack).ignore();
            Error.throwWithStackTrace(error, stack);
          });

  Stream<bool> watchMyLike(DailySongPublication publication) =>
      _likes(publication.ownerId)
          .doc(currentUid)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.data()?['publishedAt'] ==
                Timestamp.fromDate(publication.publishedAt),
          )
          .handleError((Object error, StackTrace stack) {
            reportError(error, stack).ignore();
            Error.throwWithStackTrace(error, stack);
          });

  /// One document per friend. A new publication replaces the previous like.
  Future<void> setLiked(DailySongPublication publication, bool liked) async {
    final uid = currentUid;
    if (uid == publication.ownerId ||
        !DateTime.now().isBefore(
          publication.publishedAt.add(AppUser.dailySongLifetime),
        )) {
      throw StateError('This daily song cannot be liked.');
    }
    try {
      final ref = _likes(publication.ownerId).doc(uid);
      if (liked) {
        await ref.set({
          'senderId': uid,
          'publishedAt': Timestamp.fromDate(publication.publishedAt),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // A stale card must never remove a like for a newer publication.
        await _firestore.runTransaction((tx) async {
          final snapshot = await tx.get(ref);
          if (snapshot.data()?['publishedAt'] ==
              Timestamp.fromDate(publication.publishedAt)) {
            tx.delete(ref);
          }
        });
      }
    } catch (error, stack) {
      await reportError(error, stack);
      rethrow;
    }
  }
}
