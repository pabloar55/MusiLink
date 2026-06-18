import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService({
    required FirebaseMessaging messaging,
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required SharedPreferences prefs,
    required void Function(Map<String, dynamic>) onNotificationTapped,
    required String? Function() getActiveChatId,
  }) : _messaging = messaging,
       _firestore = firestore,
       _auth = auth,
       _prefs = prefs,
       _onNotificationTapped = onNotificationTapped,
       _getActiveChatId = getActiveChatId;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final void Function(Map<String, dynamic>) _onNotificationTapped;
  final String? Function() _getActiveChatId;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'musilink_high';
  static const _channelName = 'MusiLink Notifications';
  static const _channelNoVibrationId = 'musilink_high_no_vibration';
  static const _channelNoVibrationName =
      'MusiLink Notifications (no vibration)';
  static const _channelNoSoundId = 'musilink_high_no_sound';
  static const _channelNoSoundName = 'MusiLink Notifications (no sound)';
  static const _channelSilentId = 'musilink_high_silent';
  static const _channelSilentName = 'MusiLink Notifications (silent)';
  static const _supportedPreferredLocales = {'en', 'es', 'fr'};
  static const _pendingClearUidKey = 'pending_fcm_clear_uid';
  static const kVibrationKey = 'notification_vibration';
  static const kSoundKey = 'notification_sound';
  static const _permissionDialogShownKey = 'notification_pre_dialog_shown';
  static const _apnsTokenRetries = 5;
  static const _apnsTokenRetryDelay = Duration(milliseconds: 300);

  Future<void> initialize() async {
    // 1. iOS foreground presentation options
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Create Android notification channels.
    // On Android 8+ vibration is channel-scoped, so we need two channels:
    // one with vibration and one without.
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelNoVibrationId,
        _channelNoVibrationName,
        importance: Importance.high,
        playSound: true,
        enableVibration: false,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelNoSoundId,
        _channelNoSoundName,
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelSilentId,
        _channelSilentName,
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );

    // 3. Initialize local notifications plugin
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // 4. Retry any FCM token clear that failed during a previous sign-out.
    await _retryPendingTokenClear();

    // 5. Save token silently if permission was already granted (no dialog).
    // New users will be prompted contextually from MessagesScreen.
    await _saveTokenIfGranted();

    // 6. Auto-refresh token
    _messaging.onTokenRefresh.listen((_) => _saveToken());

    // 7. Foreground message handler
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
  }

  bool get hasShownPermissionDialog =>
      _prefs.getBool(_permissionDialogShownKey) ?? false;

  Future<void> requestPermission() async {
    await _prefs.setBool(_permissionDialogShownKey, true);
    await _requestPermissionAndSaveToken();
  }

  Future<void> saveTokenIfGranted() async => _saveTokenIfGranted();

  Future<void> _saveTokenIfGranted() async {
    final settings = await _messaging.getNotificationSettings();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (granted) await _saveToken();
  }

  Future<void> _requestPermissionAndSaveToken() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _saveToken();
    }
  }

  Future<void> _saveToken() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (_requiresApnsToken && await _waitForApnsToken() == null) return;

    final String? token;
    try {
      token = await _messaging.getToken();
    } on FirebaseException catch (e, stack) {
      if (e.code == 'apns-token-not-set') return;
      await reportError(e, stack);
      rethrow;
    }
    if (token == null) return;
    await _firestore.collection(FirestoreCollections.userPrivate).doc(uid).set({
      'fcmToken': token,
      'preferredLocale': _preferredLocale(),
    }, SetOptions(merge: true));
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

    // Best-effort: revoke token from FCM. Even if this fails the token
    // will eventually expire; the Firestore cleanup below is what stops
    // immediate notification delivery to a signed-out user.
    try {
      await _messaging.deleteToken();
    } catch (e, stack) {
      await reportError(e, stack);
    }

    await _clearFcmTokenFromFirestore(uid);
  }

  Future<void> _clearFcmTokenFromFirestore(String uid) async {
    try {
      await _firestore
          .collection(FirestoreCollections.userPrivate)
          .doc(uid)
          .update({'fcmToken': FieldValue.delete()});
      await _prefs.remove(_pendingClearUidKey);
    } catch (e, stack) {
      await reportError(e, stack);
      // Queue so initialize() retries on the next app launch.
      try {
        await _prefs.setString(_pendingClearUidKey, uid);
      } catch (_) {
        // SharedPreferences failure is non-critical; error already reported.
      }
    }
  }

  Future<void> _retryPendingTokenClear() async {
    try {
      final uid = _prefs.getString(_pendingClearUidKey);
      if (uid == null) return;
      await _clearFcmTokenFromFirestore(uid);
    } catch (_) {
      // Non-critical; will retry on next launch.
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    final chatId = message.data['chatId'] as String?;
    if (chatId != null && chatId == _getActiveChatId()) return;
    final vibrate = _prefs.getBool(kVibrationKey) ?? true;
    final sound = _prefs.getBool(kSoundKey) ?? true;
    final channelId = switch ((sound, vibrate)) {
      (true, true) => _channelId,
      (true, false) => _channelNoVibrationId,
      (false, true) => _channelNoSoundId,
      (false, false) => _channelSilentId,
    };
    final channelName = switch ((sound, vibrate)) {
      (true, true) => _channelName,
      (true, false) => _channelNoVibrationName,
      (false, true) => _channelNoSoundName,
      (false, false) => _channelSilentName,
    };
    // Messages from the same chat share a stable ID so they replace each
    // other in the notification drawer instead of stacking indefinitely.
    final notifId = chatId != null ? chatId.hashCode : n.hashCode;
    _localNotifications.show(
      id: notifId,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          groupKey: chatId, // groups all notifications from the same chat
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: chatId),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Elimina de la bandeja todas las notificaciones asociadas a un chat.
  /// Cubre tanto las mostradas en foreground (`id = chatId.hashCode`) como
  /// las que pintó FCM en background/closed (`tag = chatId` / `groupKey = chatId`).
  ///
  /// En iOS la cancelación de notificaciones de FCM no es accesible desde el
  /// plugin (la identidad la asigna APNs), pero `apns-collapse-id` garantiza
  /// que sólo haya una notificación por chat en la bandeja.
  Future<void> cancelChatNotifications(String chatId) async {
    try {
      await _localNotifications.cancel(id: chatId.hashCode);
      final active = await _localNotifications.getActiveNotifications();
      for (final n in active) {
        if (n.tag != chatId && n.groupKey != chatId) continue;
        final id = n.id;
        if (id == null) continue;
        await _localNotifications.cancel(id: id, tag: n.tag);
      }
    } catch (e, stack) {
      await reportError(e, stack);
    }
  }

  Future<void> _onLocalNotificationTapped(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _onNotificationTapped(data);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('FCM: invalid notification payload: $e');
      await reportError(e, stack);
    }
  }
}
