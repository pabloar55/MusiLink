import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:musi_link/services/chat_notification_history.dart';
import 'package:musi_link/services/notification_avatar_cache.dart';
import 'package:musi_link/services/push_token_registry.dart';
import 'package:musi_link/services/web_foreground_notification.dart';
import 'package:musi_link/utils/error_reporter.dart';
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
    'friend_request' || 'daily_song_liked' => message.data['senderId'],
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
    required this._pushTokens,
    required this._prefs,
    required this._onNotificationTapped,
    required this._getActiveChatId,
    FlutterLocalNotificationsPlugin? localNotifications,
    Stream<String>? registrations,
    Stream<RemoteMessage>? foregroundMessages,
    this._prepareChat,
    this._skipLaunchNotification = false,
  }) : _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _registrations = registrations ?? _messaging.onRegistered,
       _foregroundMessages = foregroundMessages ?? FirebaseMessaging.onMessage;

  final FirebaseMessaging _messaging;
  final PushTokenRegistry _pushTokens;
  final SharedPreferences _prefs;
  final void Function(Map<String, dynamic>) _onNotificationTapped;
  final String? Function() _getActiveChatId;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final Stream<String> _registrations;
  final Stream<RemoteMessage> _foregroundMessages;
  final Future<void> Function(Map<String, dynamic>)? _prepareChat;
  final bool _skipLaunchNotification;

  /// Se puede consultar antes de runApp para evitar pasar por MainScreen.
  static Future<Map<String, dynamic>?> getLocalLaunchData({
    FlutterLocalNotificationsPlugin? localNotifications,
  }) async {
    if (kIsWeb) return null;
    try {
      final details =
          await (localNotifications ?? FlutterLocalNotificationsPlugin())
              .getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp != true || payload == null) {
        return null;
      }
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  late final _chatHistory = ChatNotificationHistory(_prefs);
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
  static const _channelDigestId = 'musilink_digest';
  static const _channelDigestName = 'MusiLink Daily Summary';
  static const kVibrationKey = 'notification_vibration';
  static const kSoundKey = 'notification_sound';
  static const _permissionDialogShownKey = 'notification_pre_dialog_shown';
  static final _notificationAvatarCache = NotificationAvatarCache();

  Future<void> initialize() async {
    _pushTokens.startSession();
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

    // Token registration is session-specific. It must run again after a
    // logout/login even though the native notification setup is app-scoped.
    await _pushTokens.restoreSession();
  }

  Future<bool> _initializePlatform() async {
    if (kIsWeb) {
      if (!await _messaging.isSupported()) return false;
      _registrations.listen(
        _pushTokens.saveRegisteredFid,
        onError: reportError,
      );
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
    if (!_skipLaunchNotification) {
      final launchDetails = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        final response = launchDetails?.notificationResponse;
        if (response != null) await _onLocalNotificationTapped(response);
      }
    }

    // 4. Persist FID registration events without registering again
    _registrations.listen(_pushTokens.saveRegisteredFid, onError: reportError);

    // 5. Foreground message handler
    _foregroundMessages.listen(_onForegroundMessage);
    return true;
  }

  bool get hasShownPermissionDialog =>
      _prefs.getBool(_permissionDialogShownKey) ?? false;

  Future<void> requestPermission() async {
    await _prefs.setBool(_permissionDialogShownKey, true);
    await _pushTokens.requestPermissionAndSaveToken();
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

  Future<void> saveTokenIfGranted() => _pushTokens.saveTokenIfGranted();

  Future<void> clearToken() => _pushTokens.clearToken();

  /// Borra los mensajes usados para agrupar avisos y retira los avisos locales
  /// de la sesión, también cuando el backend se encarga de eliminar el token.
  Future<void> clearLocalNotifications() async {
    _pushTokens.endSession();
    try {
      await _chatHistory.clear();
    } finally {
      if (!kIsWeb) await _localNotifications.cancelAll();
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (!_pushTokens.isSessionActive) return;
    final chatId = message.data['chatId'] as String?;
    if (message.data['type'] == 'new_message' && chatId != null) {
      if (chatId == _getActiveChatId()) return;
      _prepareChat?.call(message.data).ignore();
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
            history: _chatHistory,
            data: message.data,
          ),
        );
      }
      return;
    }

    // The digest invites the user to open the app, so it adds nothing while
    // the app is already in use.
    if (message.data['type'] == 'friend_digest') return;

    final n = message.notification;
    if (n == null) return;
    if (kIsWeb) {
      unawaited(
        _showWebForegroundNotification(
          message,
          sound: _prefs.getBool(kSoundKey) ?? true,
        ),
      );
      return;
    }
    final channel = _alertChannel(_prefs);
    // Repeated social notifications share a stable ID so they replace each
    // other in the notification drawer instead of stacking indefinitely.
    final notifId = foregroundNotificationId(message);
    _localNotifications.show(
      id: notifId,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
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
      history: ChatNotificationHistory(prefs),
      data: data,
    );
  }

  static Future<void> _showChatNotification({
    required FlutterLocalNotificationsPlugin localNotifications,
    required SharedPreferences prefs,
    required ChatNotificationHistory history,
    required Map<String, dynamic> data,
  }) async {
    final chatId = data['chatId'] as String?;
    final senderId = data['otherUserId'] as String?;
    final senderName = data['otherUserName'] as String?;
    final messageText = data['messageText'] as String?;
    if (chatId == null || senderName == null || messageText == null) return;
    final notificationTitle = data['notificationTitle'] as String?;
    final isGroup = data['chatType'] == 'group';
    final notificationText = notificationTitle == null || isGroup
        ? messageText
        : '$notificationTitle\n$messageText';

    final messages = await history.append(chatId, (
      senderName: senderName,
      senderId: senderId,
      text: isGroup && messageText.startsWith('$senderName: ')
          ? messageText.substring(senderName.length + 2)
          : notificationText,
      sentAt: DateTime.now(),
    ));
    final senderIconBytes = await _notificationAvatarCache.load(
      data['senderPhotoUrl'] as String?,
    );
    final senderIcon = senderIconBytes == null
        ? null
        : ByteArrayAndroidIcon(senderIconBytes);
    final channel = _alertChannel(prefs);
    final styleMessages = messages
        .map(
          (message) => Message(
            message.text,
            message.sentAt,
            Person(
              name: message.senderName,
              key: message.senderId ?? senderId,
              icon: !isGroup || message.senderId == senderId
                  ? senderIcon
                  : null,
              important: true,
            ),
          ),
        )
        .toList();
    await localNotifications.show(
      id: chatId.hashCode,
      title: notificationTitle ?? senderName,
      body: notificationText,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          category: AndroidNotificationCategory.message,
          groupKey: chatId,
          // One-to-one MessagingStyle layouts can hide the sender beside the
          // message. Keep their name in the notification header as well.
          subText: isGroup ? notificationTitle : senderName,
          styleInformation: MessagingStyleInformation(
            const Person(name: 'Tú'),
            // Android reserves conversation titles for group chats; direct
            // chats derive their title from the sender Person instead.
            groupConversation: isGroup,
            conversationTitle: isGroup ? notificationTitle : null,
            messages: styleMessages,
          ),
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  /// Canal de Android según las preferencias de sonido y vibración: en
  /// Android 8+ ambas se fijan por canal, no por aviso.
  static ({String id, String name}) _alertChannel(SharedPreferences prefs) {
    final vibrate = prefs.getBool(kVibrationKey) ?? true;
    final sound = prefs.getBool(kSoundKey) ?? true;
    return switch ((sound, vibrate)) {
      (true, true) => (id: _channelId, name: _channelName),
      (true, false) => (
        id: _channelNoVibrationId,
        name: _channelNoVibrationName,
      ),
      (false, true) => (id: _channelNoSoundId, name: _channelNoSoundName),
      (false, false) => (id: _channelSilentId, name: _channelSilentName),
    };
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
      // The backend sends the daily friend digest here so it never interrupts.
      AndroidNotificationChannel(
        _channelDigestId,
        _channelDigestName,
        importance: Importance.low,
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
      await _chatHistory.remove(chatId);
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
