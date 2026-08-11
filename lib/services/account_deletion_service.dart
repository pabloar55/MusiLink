import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/utils/firestore_collections.dart';

class AccountDeletionProgress {
  const AccountDeletionProgress({required this.status, required this.phase});

  final String status;
  final String phase;

  bool get isCompleted => status == 'completed';

  factory AccountDeletionProgress.fromMap(Map<String, dynamic> data) {
    return AccountDeletionProgress(
      status: (data['status'] ?? '').toString(),
      phase: (data['phase'] ?? '').toString(),
    );
  }
}

class AccountDeletionService {
  AccountDeletionService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _auth = auth,
       _firestore = firestore,
       _functions = functions;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<AccountDeletionProgress> requestDeletion() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Authentication is required to delete an account.');
    }

    // Reauthentication updates auth_time; force-refresh so the callable sees
    // that new value instead of a previously cached ID token.
    await user.getIdToken(true);
    final callable = _functions.httpsCallable('requestAccountDeletion');
    final result = await callable.call<dynamic>();
    final rawData = result.data;
    if (rawData is! Map) {
      throw StateError('Invalid account deletion response.');
    }
    return AccountDeletionProgress.fromMap(Map<String, dynamic>.from(rawData));
  }

  Stream<AccountDeletionProgress> watchProgress(String uid) {
    return _firestore
        .collection(FirestoreCollections.accountDeletions)
        .doc(uid)
        .snapshots()
        .where((snapshot) => snapshot.exists && snapshot.data() != null)
        .map((snapshot) => AccountDeletionProgress.fromMap(snapshot.data()!));
  }

  Future<AccountDeletionProgress?> getProgress(String uid) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.accountDeletions)
        .doc(uid)
        .get();
    final data = snapshot.data();
    return snapshot.exists && data != null
        ? AccountDeletionProgress.fromMap(data)
        : null;
  }

  Future<void> waitUntilCompleted(String uid) async {
    await watchProgress(uid).firstWhere((progress) => progress.isCompleted);
  }
}
