import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountDeletionProgress {
  const AccountDeletionProgress({required this.status, required this.phase});

  final String status;
  final String phase;

  factory AccountDeletionProgress.fromMap(Map<String, dynamic> data) {
    return AccountDeletionProgress(
      status: (data['status'] ?? '').toString(),
      phase: (data['phase'] ?? '').toString(),
    );
  }
}

class AccountDeletionService {
  AccountDeletionService({required this._auth, required this._functions});

  final FirebaseAuth _auth;
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
}
