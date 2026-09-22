import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:musi_link/utils/terms_and_conditions.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TermsAcceptanceService {
  TermsAcceptanceService(
    this._firestore,
    this._functions, {
    required this._prefs,
    required this._auth,
  });

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final SharedPreferences _prefs;
  final FirebaseAuth _auth;
  final Map<String, int> _acceptanceRevisions = {};

  static String _cacheKey(String uid) => 'terms_accepted_version_$uid';

  bool hasCachedAcceptance(String uid) {
    try {
      return _prefs.getString(_cacheKey(uid)) == TermsAndConditions.version;
    } catch (error, stack) {
      unawaited(reportError(error, stack));
      return false;
    }
  }

  Future<void> _cacheAcceptance(String uid, bool accepted) async {
    try {
      if (accepted) {
        await _prefs.setString(_cacheKey(uid), TermsAndConditions.version);
      } else {
        await _prefs.remove(_cacheKey(uid));
      }
    } catch (error, stack) {
      // Un fallo de persistencia local no invalida la respuesta del servidor.
      unawaited(reportError(error, stack));
    }
  }

  Future<bool> hasAcceptedCurrentVersion(String uid) async {
    final revision = _acceptanceRevisions[uid] ?? 0;
    final snapshot = await _firestore
        .collection(FirestoreCollections.userPrivate)
        .doc(uid)
        .collection(FirestoreCollections.termsAcceptances)
        .doc('current')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    // Una lectura iniciada antes de aceptar no debe borrar esa confirmación.
    if (revision != (_acceptanceRevisions[uid] ?? 0)) return true;
    final accepted = snapshot.data()?['version'] == TermsAndConditions.version;
    await _cacheAcceptance(uid, accepted);
    return accepted;
  }

  Future<void> acceptCurrentVersion() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Authentication is required.');
    final callable = _functions.httpsCallable('acceptTerms');
    final result = await callable.call<Map<String, dynamic>>({
      'version': TermsAndConditions.version,
    });
    if (result.data['version'] != TermsAndConditions.version) {
      throw StateError('The terms acceptance was not confirmed.');
    }
    if (_auth.currentUser?.uid != uid) {
      throw StateError('The account changed during terms acceptance.');
    }
    _acceptanceRevisions[uid] = (_acceptanceRevisions[uid] ?? 0) + 1;
    await _cacheAcceptance(uid, true);
  }
}
