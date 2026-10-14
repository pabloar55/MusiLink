import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registra el token push de esta instalación para la sesión actual y lo
/// retira al cerrarla.
///
/// Una escritura iniciada antes de cerrar sesión nunca vuelve a registrar el
/// token retirado, y la retirada sobrevive a fallos de red y reinicios: cada
/// cuenta pendiente queda marcada hasta que su token se borra en Firestore.
class PushTokenRegistry {
  PushTokenRegistry({
    required this._messaging,
    required this._firestore,
    required this._auth,
    required this._prefs,
  });

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SharedPreferences _prefs;

  int _tokenGeneration = 0;
  bool _signingOut = false;

  static const _supportedPreferredLocales = {'el', 'en', 'es', 'fr'};
  static const _pendingClearUidKey = 'pending_fcm_clear_uid';
  static const _pendingClearUidsKey = 'pending_fcm_clear_uids';
  static const _tokenCleanupTimeout = Duration(seconds: 2);
  static const _installationIdKey = 'push_installation_id';
  static const _webVapidKey =
      'BHWDoNtHqOTGikK1rCJeWntcKQUiv763Z1YtY96MP2DzePOFHFtw8dxy7mGME7EnkajPy3q6DfjdMU34yiq8sEc';
  static const _apnsTokenRetries = 5;
  static const _apnsTokenRetryDelay = Duration(milliseconds: 300);

  /// False desde que se cierra la sesión hasta que empieza la siguiente.
  bool get isSessionActive => !_signingOut;

  void startSession() => _signingOut = false;

  /// Descarta las escrituras de token que sigan en curso.
  void endSession() {
    _signingOut = true;
    _tokenGeneration++;
  }

  /// Termina la limpieza pendiente de la cuenta actual y registra su token.
  /// Debe repetirse en cada sesión, aunque la plataforma ya esté inicializada.
  Future<void> restoreSession() async {
    await _retryPendingTokenClear();
    await saveTokenIfGranted();
  }

  Future<void> saveTokenIfGranted() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) await saveToken();
    } catch (error, stack) {
      // Token registration is best-effort. A transient messaging failure must
      // not escape from lifecycle callbacks as an uncaught async exception.
      await reportError(error, stack);
    }
  }

  Future<void> requestPermissionAndSaveToken() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await saveToken();
    }
  }

  Future<void> saveToken() async {
    final uid = _auth.currentUser?.uid;
    final generation = _tokenGeneration;
    if (uid == null || _signingOut) return;

    try {
      // Authentication precedes profile creation. Push rules require a
      // published profile; MainScreen retries when onboarding completes.
      final profile = await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!profile.exists ||
          profile.data()?['username'] == null ||
          profile.data()?['username'] == 'deleted_user') {
        return;
      }
      if (_requiresApnsToken && await _waitForApnsToken() == null) return;

      final token = await _getToken();
      if (token == null) return;
      final installationId = await _installationId();
      // A refresh started before logout must not re-register the removed token.
      if (_signingOut ||
          generation != _tokenGeneration ||
          _auth.currentUser?.uid != uid) {
        return;
      }
      final privateUserRef = _firestore
          .collection(FirestoreCollections.userPrivate)
          .doc(uid);
      final tokenRef = privateUserRef
          .collection(FirestoreCollections.pushTokens)
          .doc(installationId);
      final batch = _firestore.batch();
      batch.set(privateUserRef, {
        'preferredLocale': _preferredLocale(),
        // The backend schedules the daily friend digest in local time.
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      }, SetOptions(merge: true));
      batch.set(tokenRef, {
        'token': token,
        'platform': _pushPlatform(),
        'preferredLocale': _preferredLocale(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (error, stack) {
      if (error.code == 'apns-token-not-set') return;
      if (error.code == 'permission-denied' &&
          await _tokenWriteIsObsolete(uid)) {
        return;
      }
      await reportError(error, stack);
    } catch (error, stack) {
      await reportError(error, stack);
    }
  }

  Future<bool> _tokenWriteIsObsolete(String uid) async {
    // The write may have started before sign-out and reached Firestore after
    // the authenticated session disappeared.
    if (_auth.currentUser?.uid != uid) return true;

    try {
      // Account deletion deliberately freezes all client writes. Confirm the
      // durable job before treating its permission denial as expected, so a
      // genuine rules regression for an active user is still reported.
      final deletionJob = await _firestore
          .collection(FirestoreCollections.accountDeletions)
          .doc(uid)
          .get();
      return deletionJob.exists;
    } catch (_) {
      return false;
    }
  }

  String _pushPlatform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      _ => 'android',
    };
  }

  Future<String?> _getToken() => _messaging.getToken(
    vapidKey: kIsWeb ? _webVapidKey : null,
    serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null,
  );

  Future<String> _installationId() async {
    final existing = _prefs.getString(_installationIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final id = base64Url.encode(bytes).replaceAll('=', '');
    await _prefs.setString(_installationIdKey, id);
    return id;
  }

  bool get _requiresApnsToken =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<String?> _waitForApnsToken() async {
    for (var attempt = 0; attempt < _apnsTokenRetries; attempt++) {
      final token = await _messaging.getAPNSToken();
      if (token != null) return token;
      await Future<void>.delayed(_apnsTokenRetryDelay);
    }
    return null;
  }

  String _preferredLocale() {
    final languageCode = PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    if (_supportedPreferredLocales.contains(languageCode)) {
      return languageCode;
    }
    return 'en';
  }

  Future<void> clearToken() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    endSession();

    // Persist recovery before any network work. Multiple accounts can sign out
    // offline on this installation without overwriting one another's cleanup.
    try {
      final pending = _pendingClearUids()..add(uid);
      await _prefs.setStringList(_pendingClearUidsKey, pending.toList());
    } catch (e, stack) {
      unawaited(reportError(e, stack));
    }

    await Future.wait([
      _revokeMessagingToken(),
      _clearFcmTokenFromFirestore(uid),
    ]);
  }

  Future<void> _revokeMessagingToken() async {
    try {
      await _deleteMessagingToken().timeout(_tokenCleanupTimeout);
    } on TimeoutException {
      // FCM availability must not delay the independent Firestore removal.
    } catch (e, stack) {
      unawaited(reportError(e, stack));
    }
  }

  Future<void> _deleteMessagingToken() async {
    await _messaging.deleteToken();
    // A timeout does not cancel the native operation. If another session has
    // started by the time it finishes, repair that session's token registration.
    if (!_signingOut && _auth.currentUser != null) {
      unawaited(saveTokenIfGranted());
    }
  }

  Set<String> _pendingClearUids() => {
    ...?_prefs.getStringList(_pendingClearUidsKey),
    if (_prefs.getString(_pendingClearUidKey) case final String uid) uid,
  };

  Future<void> _forgetPendingClear(String uid) async {
    final pending = _pendingClearUids()..remove(uid);
    await _prefs.setStringList(_pendingClearUidsKey, pending.toList());
    if (_prefs.getString(_pendingClearUidKey) == uid) {
      await _prefs.remove(_pendingClearUidKey);
    }
  }

  Future<void> _clearFcmTokenFromFirestore(String uid) async {
    try {
      final privateUserRef = _firestore
          .collection(FirestoreCollections.userPrivate)
          .doc(uid);
      final installationId = await _installationId();
      if (_auth.currentUser?.uid != uid) return;
      await privateUserRef
          .collection(FirestoreCollections.pushTokens)
          .doc(installationId)
          .delete()
          .timeout(_tokenCleanupTimeout);

      await _forgetPendingClear(uid);
    } on TimeoutException {
      // Firestore may keep the write queued offline. Keep the durable marker
      // even if that original write eventually finishes after this timeout.
    } catch (e, stack) {
      unawaited(reportError(e, stack));
    }
  }

  Future<void> _retryPendingTokenClear() async {
    try {
      // Rules only allow deleting the signed-in user's tokens. Retain other
      // users' markers until they sign in again, then clear before registering.
      final uid = _auth.currentUser?.uid;
      if (uid == null || !_pendingClearUids().contains(uid)) return;
      await _clearFcmTokenFromFirestore(uid);
    } catch (_) {
      // Non-critical; will retry on next launch.
    }
  }
}
