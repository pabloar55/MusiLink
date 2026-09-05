import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:musi_link/services/notification_avatar_cache.dart';
import 'package:musi_link/services/web_foreground_notification.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PushPermissionState { unsupported, notDetermined, denied, enabled }

int _stableNotificationId(String key) {
  var hash = 0;
  for (final codeUnit in key.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash;
}

@visibleForTesting
int foregroundNotificationId(RemoteMessage message) {
  final type = message.data['type'];
  final relatedUserId = switch (type) {
    'friend_request' => message.data['senderId'],
    'friend_request_accepted' => message.data['accepterId'],
    _ => null,
  };
  if (type is String && relatedUserId is String && relatedUserId.isNotEmpty) {
    return _stableNotificationId('$type:$relatedUserId');
  }

  final platformTag = message.notification?.android?.tag;
  if (platformTag != null && platformTag.isNotEmpty) {
    return _stableNotificationId(platformTag);
  }

  return message.messageId?.hashCode ?? message.notification.hashCode;
}

class NotificationService {
  NotificationService({
    required this._messaging,
    required this._firestore,
    required this._auth,
    required this._prefs,
    required this._onNotificationTapped,
    required this._getActiveChatId,
    FlutterLocalNotificationsPlugin? localNotifications,
    Stream<String>? tokenRefreshes,
    Stream<RemoteMessage>? foregroundMessages,
  }) : _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _tokenRefreshes = tokenRefreshes ?? _messaging.onTokenRefresh,
       _foregroundMessages = foregroundMessages ?? FirebaseMessaging.onMessage;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final void Function(Map<String, dynamic>) _onNotificationTapped;
  final String? Function() _getActiveChatId;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final Stream<String> _tokenRefreshes;
  final Stream<RemoteMessage> _foregroundMessages;

  Future<bool>? _platformInitialization;

  static const _channelId = 'musilink_high';
  static const _channelName = 'MusiLink Notifications';
  static const _channelNoVibrationId = 'musilink_high_no_vibration';
  static const _channelNoVibrationName =
      'MusiLink Notifications (no vibration)';
  static const _channelNoSoundId = 'musilink_high_no_sound';
  static const _channelNoSoundName = 'MusiLink Notifications (no sound)';
  static const _channelSilentId = 'musilink_high_silent';
  static const _channelSilentName = 'MusiLink Notifications (silent)';
  static const _supportedPreferredLocales = {'el', 'en', 'es', 'fr'};
  static const _pendingClearUidKey = 'pending_fcm_clear_uid';
  static const _installationIdKey = 'push_installation_id';
  static const _webVapidKey =
      'BHWDoNtHqOTGikK1rCJeWntcKQUiv763Z1YtY96MP2DzePOFHFtw8dxy7mGME7EnkajPy3q6DfjdMU34yiq8sEc';
  static const kVibrationKey = 'notification_vibration';
  static const kSoundKey = 'notification_sound';
  static const _permissionDialogShownKey = 'notification_pre_dialog_shown';
  static const _apnsTokenRetries = 5;
  static const _apnsTokenRetryDelay = Duration(milliseconds: 300);
  static const _chatHistoryKey = 'chat_notification_history';
  static const _maxMessagesPerChat = 5;
  static final _notificationAvatarCache = NotificationAvatarCache();

  Future<void> initialize() async {
    final initialization = _platformInitialization ??= _initializePlatform();
    final bool supported;
    try {
      supported = await initialization;
    } catch (_) {
      if (identical(_platformInitialization, initialization)) {
        _platformInitialization = null;
      }
      rethrow;
    }
    if (!supported) return;

    // These operations are session-specific. They must run again after a
    // logout/login even though the native notification setup is app-scoped.
    await _retryPendingTokenClear();
    await _saveTokenIfGranted();
  }

  Future<bool> _initializePlatform() async {
    if (kIsWeb) {
      if (!await _messaging.isSupported()) return false;
      _tokenRefreshes.listen((_) => _saveToken());
      _foregroundMessages.listen(_onForegroundMessage);
      return true;
    }

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

    // 4. Auto-refresh token
    _tokenRefreshes.listen((_) => _saveToken());

    // 5. Foreground message handler
    _foregroundMessages.listen(_onForegroundMessage);
    return true;
  }

  bool get hasShownPermissionDialog =>
      _prefs.getBool(_permissionDialogShownKey) ?? false;

  Future<void> requestPermission() async {
    await _prefs.setBool(_permissionDialogShownKey, true);
    await _requestPermissionAndSaveToken();
  }

  Future<PushPermissionState> getPermissionState() async {
    if (kIsWeb && !await _messaging.isSupported()) {
      return PushPermissionState.unsupported;
    }
    final settings = await _messaging.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermissionState.enabled,
      AuthorizationStatus.denied => PushPermissionState.denied,
      AuthorizationStatus.notDetermined => PushPermissionState.notDetermined,
      AuthorizationStatus.deniedPermanently => PushPermissionState.denied,
    };
  }

  Future<void> saveTokenIfGranted() async => _saveTokenIfGranted();

  Future<void> _saveTokenIfGranted() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) await _saveToken();
    } catch (error, stack) {
      // Token registration is best-effort. A transient messaging failure must
      // not escape from lifecycle callbacks as an uncaught async exception.
      await reportError(error, stack);
    }
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

    try {
      if (_requiresApnsToken && await _waitForApnsToken() == null) return;

      final token = await _getToken();
      if (token == null) return;
      final installationId = await _installationId();
      final privateUserRef = _firestore
          .collection(FirestoreCollections.userPrivate)
          .doc(uid);
      final tokenRef = privateUserRef
          .collection(FirestoreCollections.pushTokens)
          .doc(installationId);
      final batch = _firestore.batch();
      batch.set(privateUserRef, {
        'preferredLocale': _preferredLocale(),
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
      final privateUserRef = _firestore
          .collection(FirestoreCollections.userPrivate)
          .doc(uid);
      final installationId = await _installationId();
      await privateUserRef
          .collection(FirestoreCollections.pushTokens)
          .doc(installationId)
          .delete();

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
      if (kIsWeb) {
        unawaited(_showWebForegroundNotification(message));
        return;
      }
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
    if (kIsWeb) {
      unawaited(_showWebForegroundNotification(message, sound: sound));
      return;
    }
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
    // Repeated social notifications share a stable ID so they replace each
    // other in the notification drawer instead of stacking indefinitely.
    final notifId = foregroundNotificationId(message);
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

  Future<void> _showWebForegroundNotification(
    RemoteMessage message, {
    bool? sound,
  }) async {
    try {
      await showWebForegroundNotification(
        message,
        silent: !(sound ?? (_prefs.getBool(kSoundKey) ?? true)),
      );
    } catch (error, stack) {
      await reportError(error, stack);
    }
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
    final senderIconBytes = await _notificationAvatarCache.load(
      data['senderPhotoUrl'] as String?,
    );
    final senderIcon = senderIconBytes == null
        ? null
        : ByteArrayAndroidIcon(senderIconBytes);
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
