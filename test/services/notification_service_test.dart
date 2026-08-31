import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockLocalNotifications extends Mock
    implements FlutterLocalNotificationsPlugin {}

class MockNotificationSettings extends Mock implements NotificationSettings {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('friend request notifications reuse an ID per sender', () {
    const first = RemoteMessage(
      messageId: 'message-1',
      data: {'type': 'friend_request', 'senderId': 'alice'},
      notification: RemoteNotification(title: 'MusiLink', body: 'Solicitud'),
    );
    const repeated = RemoteMessage(
      messageId: 'message-2',
      data: {'type': 'friend_request', 'senderId': 'alice'},
      notification: RemoteNotification(title: 'MusiLink', body: 'Solicitud'),
    );
    const otherSender = RemoteMessage(
      messageId: 'message-3',
      data: {'type': 'friend_request', 'senderId': 'bob'},
      notification: RemoteNotification(title: 'MusiLink', body: 'Solicitud'),
    );

    expect(foregroundNotificationId(first), foregroundNotificationId(repeated));
    expect(
      foregroundNotificationId(first),
      isNot(foregroundNotificationId(otherSender)),
    );
  });

  test('accepted request notifications reuse an ID per accepter', () {
    const first = RemoteMessage(
      messageId: 'message-1',
      data: {'type': 'friend_request_accepted', 'accepterId': 'alice'},
      notification: RemoteNotification(title: 'MusiLink', body: 'Aceptada'),
    );
    const repeated = RemoteMessage(
      messageId: 'message-2',
      data: {'type': 'friend_request_accepted', 'accepterId': 'alice'},
      notification: RemoteNotification(title: 'MusiLink', body: 'Aceptada'),
    );

    expect(foregroundNotificationId(first), foregroundNotificationId(repeated));
  });

  test('processes launch notification only once across logins', () async {
    final messaging = MockFirebaseMessaging();
    final firestore = MockFirebaseFirestore();
    final auth = MockFirebaseAuth();
    final localNotifications = MockLocalNotifications();
    final settings = MockNotificationSettings();
    final prefs = await SharedPreferences.getInstance();
    final handledNotifications = <Map<String, dynamic>>[];

    when(
      () => messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      ),
    ).thenAnswer((_) async {});
    when(() => messaging.getNotificationSettings())
        .thenAnswer((_) async => settings);
    when(() => settings.authorizationStatus)
        .thenReturn(AuthorizationStatus.denied);
    when(() => auth.currentUser).thenReturn(null);
    when(
      () => localNotifications.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse: any(
          named: 'onDidReceiveNotificationResponse',
        ),
      ),
    ).thenAnswer((_) async => true);
    when(() => localNotifications.getNotificationAppLaunchDetails()).thenAnswer(
      (_) async => const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: '{"type":"friend_request"}',
        ),
      ),
    );

    final service = NotificationService(
      messaging: messaging,
      firestore: firestore,
      auth: auth,
      prefs: prefs,
      onNotificationTapped: handledNotifications.add,
      getActiveChatId: () => null,
      localNotifications: localNotifications,
      tokenRefreshes: const Stream.empty(),
      foregroundMessages: const Stream.empty(),
    );

    await service.initialize();
    await service.initialize();

    expect(handledNotifications, [
      {'type': 'friend_request'},
    ]);
    verify(() => localNotifications.getNotificationAppLaunchDetails())
        .called(1);
    verify(
      () => messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      ),
    ).called(1);
    verify(() => messaging.getNotificationSettings()).called(2);
  });
}
