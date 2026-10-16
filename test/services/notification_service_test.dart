import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/push_token_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockPushTokenRegistry extends Mock implements PushTokenRegistry {}

class MockLocalNotifications extends Mock
    implements FlutterLocalNotificationsPlugin {}

MockPushTokenRegistry activePushTokens() {
  final pushTokens = MockPushTokenRegistry();
  when(() => pushTokens.isSessionActive).thenReturn(true);
  when(() => pushTokens.restoreSession()).thenAnswer((_) async {});
  return pushTokens;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const NotificationDetails());
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

  test(
    'clears chat notification history, displayed notices and the push session',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final localNotifications = MockLocalNotifications();
      final pushTokens = activePushTokens();
      await prefs.setString('chat_notification_history', '{"chat":[]}');
      await prefs.setBool('notification_sound', false);
      when(() => localNotifications.cancelAll()).thenAnswer((_) async {});
      final service = NotificationService(
        messaging: MockFirebaseMessaging(),
        pushTokens: pushTokens,
        prefs: prefs,
        onNotificationTapped: (_) {},
        getActiveChatId: () => null,
        localNotifications: localNotifications,
        registrations: const Stream.empty(),
        foregroundMessages: const Stream.empty(),
      );

      await service.clearLocalNotifications();

      expect(prefs.getString('chat_notification_history'), isNull);
      expect(prefs.getBool('notification_sound'), isFalse);
      verify(() => localNotifications.cancelAll()).called(1);
      verify(pushTokens.endSession).called(1);
    },
  );

  test(
    'chat notifications keep the sender in the header and recent messages',
    () async {
      final messaging = MockFirebaseMessaging();
      final localNotifications = MockLocalNotifications();
      final foreground = StreamController<RemoteMessage>();
      addTearDown(foreground.close);
      final prefs = await SharedPreferences.getInstance();
      final shown = StreamController<Invocation>();
      addTearDown(shown.close);
      final notifications = StreamIterator(shown.stream);
      addTearDown(notifications.cancel);

      when(
        () => messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        ),
      ).thenAnswer((_) async {});
      when(
        () => localNotifications.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse: any(
            named: 'onDidReceiveNotificationResponse',
          ),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => localNotifications.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((invocation) async => shown.add(invocation));

      final service = NotificationService(
        messaging: messaging,
        pushTokens: activePushTokens(),
        prefs: prefs,
        onNotificationTapped: (_) {},
        getActiveChatId: () => null,
        skipLaunchNotification: true,
        localNotifications: localNotifications,
        registrations: const Stream.empty(),
        foregroundMessages: foreground.stream,
      );
      await service.initialize();

      for (var i = 0; i < 6; i++) {
        final data = {
          'type': 'new_message',
          'chatId': 'chat',
          'otherUserId': 'alice',
          'otherUserName': 'Alice',
          'messageText': 'Message $i',
        };
        foreground.add(RemoteMessage(data: data));
        expect(await notifications.moveNext(), isTrue);
        final args = notifications.current.namedArguments;
        final android =
            (args[#notificationDetails] as NotificationDetails).android!;
        final style = android.styleInformation! as MessagingStyleInformation;

        expect(args[#id], 'chat'.hashCode);
        expect(args[#title], 'Alice');
        expect(args[#body], 'Message $i');
        expect(jsonDecode(args[#payload] as String), data);
        expect(android.subText, 'Alice');
        expect(style.groupConversation, isFalse);
        expect(style.conversationTitle, isNull);
        expect(style.messages!.map((message) => message.text), [
          for (var j = i < 5 ? 0 : i - 4; j <= i; j++) 'Message $j',
        ]);
        for (final message in style.messages!) {
          expect(message.person!.name, 'Alice');
          expect(message.person!.key, 'alice');
          expect(message.person!.icon, isNull);
        }
      }
      foreground.add(
        const RemoteMessage(
          data: {
            'type': 'new_message',
            'chatId': 'chat',
            'otherUserId': 'alice',
            'otherUserName': 'Alice',
            'messageText': 'Me encanta',
            'notificationTitle': 'Alice ha respondido a tu canción',
          },
        ),
      );
      expect(await notifications.moveNext(), isTrue);
      final replyArgs = notifications.current.namedArguments;
      expect(replyArgs[#title], 'Alice ha respondido a tu canción');
      expect(replyArgs[#body], 'Alice ha respondido a tu canción\nMe encanta');
      final replyStyle =
          (replyArgs[#notificationDetails] as NotificationDetails)
                  .android!
                  .styleInformation!
              as MessagingStyleInformation;
      expect(
        replyStyle.messages!.last.text,
        'Alice ha respondido a tu canción\nMe encanta',
      );
    },
  );

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

  test(
    'reads Android launch payload before initializing notification listeners',
    () async {
      final local = MockLocalNotifications();
      when(() => local.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload:
                '{"type":"new_message","chatId":"chat","otherUserId":"sender"}',
          ),
        ),
      );
      expect(
        await NotificationService.getLocalLaunchData(localNotifications: local),
        {'type': 'new_message', 'chatId': 'chat', 'otherUserId': 'sender'},
      );
      when(() => local.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '{bad',
          ),
        ),
      );
      expect(
        await NotificationService.getLocalLaunchData(localNotifications: local),
        isNull,
      );
    },
  );

  for (final alreadyHandled in [false, true]) {
    test(
      'processes launch notification once; handled at startup: $alreadyHandled',
      () async {
        final messaging = MockFirebaseMessaging();
        final pushTokens = activePushTokens();
        final registrations = StreamController<String>();
        addTearDown(registrations.close);
        when(() => pushTokens.saveRegisteredFid(any()))
            .thenAnswer((_) async {});
        final localNotifications = MockLocalNotifications();
        final prefs = await SharedPreferences.getInstance();
        final handledNotifications = <Map<String, dynamic>>[];
        final preparedChats = <Map<String, dynamic>>[];
        String? activeChat = 'chat';
        final foreground = StreamController<RemoteMessage>();
        addTearDown(foreground.close);

        when(
          () => messaging.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          ),
        ).thenAnswer((_) async {});
        when(
          () => localNotifications.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse: any(
              named: 'onDidReceiveNotificationResponse',
            ),
          ),
        ).thenAnswer((_) async => true);
        when(() => localNotifications.getNotificationAppLaunchDetails())
            .thenAnswer(
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
          pushTokens: pushTokens,
          prefs: prefs,
          onNotificationTapped: handledNotifications.add,
          getActiveChatId: () => activeChat,
          skipLaunchNotification: alreadyHandled,
          prepareChat: (data) async {
            preparedChats.add(data);
          },
          localNotifications: localNotifications,
          registrations: registrations.stream,
          foregroundMessages: foreground.stream,
        );

        await service.initialize();
        await service.initialize();
        registrations.add('c123456789012345678901');
        await Future<void>.delayed(Duration.zero);
        verify(() => pushTokens.saveRegisteredFid('c123456789012345678901'))
            .called(1);
        verifyNever(pushTokens.saveToken);

        expect(
          handledNotifications,
          alreadyHandled
              ? isEmpty
              : [
                  {'type': 'friend_request'},
                ],
        );
        if (alreadyHandled) {
          verifyNever(
            () => localNotifications.getNotificationAppLaunchDetails(),
          );
        } else {
          verify(() => localNotifications.getNotificationAppLaunchDetails())
              .called(1);
        }
        foreground.add(
          const RemoteMessage(data: {'type': 'new_message', 'chatId': 'chat'}),
        );
        await Future<void>.delayed(Duration.zero);
        expect(preparedChats, isEmpty);
        activeChat = null;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        foreground.add(
          const RemoteMessage(data: {'type': 'new_message', 'chatId': 'chat'}),
        );
        await Future<void>.delayed(Duration.zero);
        expect(preparedChats, [
          {'type': 'new_message', 'chatId': 'chat'},
        ]);
        when(() => pushTokens.isSessionActive).thenReturn(false);
        foreground.add(
          const RemoteMessage(data: {'type': 'new_message', 'chatId': 'chat'}),
        );
        await Future<void>.delayed(Duration.zero);
        expect(preparedChats, hasLength(1));
        verify(
          () => messaging.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          ),
        ).called(1);
        // Each session restores its token even if the platform is ready.
        verify(pushTokens.startSession).called(2);
        verify(pushTokens.restoreSession).called(2);
      },
    );
  }
}
