import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:musi_link/utils/terms_and_conditions.dart';

class TermsAcceptanceService {
  const TermsAcceptanceService(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<bool> hasAcceptedCurrentVersion(String uid) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.userPrivate)
        .doc(uid)
        .collection(FirestoreCollections.termsAcceptances)
        .doc('current')
        .get(const GetOptions(source: Source.server));
    return snapshot.data()?['version'] == TermsAndConditions.version;
  }

  Future<void> acceptCurrentVersion() async {
    final callable = _functions.httpsCallable('acceptTerms');
    final result = await callable.call<Map<String, dynamic>>({
      'version': TermsAndConditions.version,
    });
    if (result.data['version'] != TermsAndConditions.version) {
      throw StateError('The terms acceptance was not confirmed.');
    }
  }
}
