import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
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
  static const _chatHistoryKey = 'chat_notification_history';
  static const _maxMessagesPerChat = 5;
  static const _avatarDownloadTimeout = Duration(seconds: 3);
  static const _maxAvatarBytes = 1024 * 1024;

  Future<void> initialize() async {
    if (kIsWeb) return;

    // 1. iOS foreground presentation options
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Create Android notification channels.
    // On Android 8+ vibration is channel-scoped, so we need two channels:
    // one with vibration and one without.
    await _createAndroidChannels(_localNotifications);

    // 3. Initialize local notifications plugin
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails?.notificationResponse;
      if (response != null) await _onLocalNotificationTapped(response);
    }

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
    if (kIsWeb) return;

    final settings = await _messaging.getNotificationSettings();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (granted) await _saveToken();
  }

  Future<void> _requestPermissionAndSaveToken() async {
    if (kIsWeb) return;

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
    if (kIsWeb) return;

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
    if (kIsWeb) return;

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
    final chatId = message.data['chatId'] as String?;
    if (message.data['type'] == 'new_message' && chatId != null) {
      if (chatId == _getActiveChatId()) return;
      // Chat pushes are data-only on Android. Updating a local
      // MessagingStyle notification keeps their recent messages together.
      if (defaultTargetPlatform == TargetPlatform.android) {
        unawaited(
          _showChatNotification(
            localNotifications: _localNotifications,
            prefs: _prefs,
            data: message.data,
          ),
        );
      }
      return;
    }

    final n = message.notification;
    if (n == null) return;
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

  /// Handles an Android data-only chat push while the app is in the
  /// background or terminated. It must not depend on FirebaseAuth or UI state.
  @pragma('vm:entry-point')
  static Future<void> showBackgroundChatNotification(
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = await SharedPreferences.getInstance();
    final localNotifications = FlutterLocalNotificationsPlugin();
    await _createAndroidChannels(localNotifications);
    await localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    await _showChatNotification(
      localNotifications: localNotifications,
      prefs: prefs,
      data: data,
    );
  }

  static Future<void> _showChatNotification({
    required FlutterLocalNotificationsPlugin localNotifications,
    required SharedPreferences prefs,
    required Map<String, dynamic> data,
  }) async {
    final chatId = data['chatId'] as String?;
    final senderId = data['otherUserId'] as String?;
    final senderName = data['otherUserName'] as String?;
    final messageText = data['messageText'] as String?;
    if (chatId == null || senderName == null || messageText == null) return;

    final messages = await _appendChatMessage(
      prefs: prefs,
      chatId: chatId,
      senderName: senderName,
      text: messageText,
    );
    final senderIcon = await _downloadSenderIcon(
      data['senderPhotoUrl'] as String?,
    );
    final vibrate = prefs.getBool(kVibrationKey) ?? true;
    final sound = prefs.getBool(kSoundKey) ?? true;
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
    final styleMessages = messages
        .map(
          (message) => Message(
            message['text']! as String,
            DateTime.fromMillisecondsSinceEpoch(message['timestamp']! as int),
            Person(
              name: message['senderName']! as String,
              key: senderId,
              icon: senderIcon,
              important: true,
            ),
          ),
        )
        .toList();
    await localNotifications.show(
      id: chatId.hashCode,
      title: senderName,
      body: messageText,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          category: AndroidNotificationCategory.message,
          groupKey: chatId,
          styleInformation: MessagingStyleInformation(
            const Person(name: 'Tú'),
            conversationTitle: senderName,
            groupConversation: false,
            messages: styleMessages,
          ),
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  static Future<AndroidIcon<Object>?> _downloadSenderIcon(
    String? rawUrl,
  ) async {
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;

    try {
      final response = await http.get(uri).timeout(_avatarDownloadTimeout);
      final contentType = response.headers['content-type'];
      final isImage =
          contentType == null || contentType.toLowerCase().startsWith('image/');
      if (response.statusCode != 200 ||
          !isImage ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > _maxAvatarBytes) {
        return null;
      }
      return ByteArrayAndroidIcon(response.bodyBytes);
    } catch (_) {
      // The avatar is optional; notification delivery must not depend on it.
      return null;
    }
  }

  static Future<List<Map<String, Object>>> _appendChatMessage({
    required SharedPreferences prefs,
    required String chatId,
    required String senderName,
    required String text,
  }) async {
    final rawHistory = prefs.getString(_chatHistoryKey);
    final history = rawHistory == null
        ? <String, dynamic>{}
        : jsonDecode(rawHistory) as Map<String, dynamic>;
    final messages = (history[chatId] as List<dynamic>? ?? <dynamic>[])
        .map((item) => Map<String, Object>.from(item as Map))
        .toList();
    messages.add({
      'senderName': senderName,
      'text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    if (messages.length > _maxMessagesPerChat) {
      messages.removeRange(0, messages.length - _maxMessagesPerChat);
    }
    history[chatId] = messages;
    await prefs.setString(_chatHistoryKey, jsonEncode(history));
    return messages;
  }

  static Future<void> _createAndroidChannels(
    FlutterLocalNotificationsPlugin localNotifications,
  ) async {
    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final channel in const [
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _channelNoVibrationId,
        _channelNoVibrationName,
        importance: Importance.high,
        playSound: true,
        enableVibration: false,
      ),
      AndroidNotificationChannel(
        _channelNoSoundId,
        _channelNoSoundName,
        importance: Importance.high,
        playSound: false,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _channelSilentId,
        _channelSilentName,
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    ]) {
      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  /// Elimina de la bandeja todas las notificaciones asociadas a un chat.
  /// Android uses `id = chatId.hashCode` in every app state; iOS keeps its
  /// native APNs grouping through `apns-collapse-id`.
  Future<void> cancelChatNotifications(String chatId) async {
    try {
      await _localNotifications.cancel(id: chatId.hashCode);
      final rawHistory = _prefs.getString(_chatHistoryKey);
      if (rawHistory != null) {
        final history = jsonDecode(rawHistory) as Map<String, dynamic>;
        history.remove(chatId);
        await _prefs.setString(_chatHistoryKey, jsonEncode(history));
      }
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
