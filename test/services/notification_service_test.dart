// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

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

class MockUser extends Mock implements User {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockWriteBatch extends Mock implements WriteBatch {}

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

  group('token cleanup', () {
    late MockFirebaseMessaging messaging;
    late MockFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockUser user;
    late MockDocumentReference tokenRef;
    late MockNotificationSettings settings;
    late MockWriteBatch batch;
    late SharedPreferences prefs;
    late NotificationService service;

    setUp(() async {
      debugDefaultTargetPlatformOverride = null;
      SharedPreferences.setMockInitialValues({
        'push_installation_id': 'installation',
      });
      messaging = MockFirebaseMessaging();
      firestore = MockFirebaseFirestore();
      auth = MockFirebaseAuth();
      user = MockUser();
      tokenRef = MockDocumentReference();
      settings = MockNotificationSettings();
      batch = MockWriteBatch();
      final privateUsers = MockCollectionReference();
      final privateUser = MockDocumentReference();
      final tokens = MockCollectionReference();
      final localNotifications = MockLocalNotifications();
      prefs = await SharedPreferences.getInstance();

      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('alice');
      when(() => firestore.collection('user_private')).thenReturn(privateUsers);
      when(() => privateUsers.doc(any())).thenReturn(privateUser);
      when(() => privateUser.collection('push_tokens')).thenReturn(tokens);
      when(() => tokens.doc('installation')).thenReturn(tokenRef);
      when(() => tokenRef.delete()).thenAnswer((_) async {});
      when(() => messaging.deleteToken()).thenAnswer((_) async {});
      when(() => messaging.getNotificationSettings())
          .thenAnswer((_) async => settings);
      when(() => settings.authorizationStatus)
          .thenReturn(AuthorizationStatus.authorized);
      when(
        () => messaging.getToken(vapidKey: null, serviceWorkerScriptPath: null),
      ).thenAnswer((_) async => 'new-token');
      when(() => firestore.batch()).thenReturn(batch);
      when(() => batch.commit()).thenAnswer((_) async {});
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
          .thenAnswer((_) async => null);

      service = NotificationService(
        messaging: messaging,
        firestore: firestore,
        auth: auth,
        prefs: prefs,
        onNotificationTapped: (_) {},
        getActiveChatId: () => null,
        localNotifications: localNotifications,
        tokenRefreshes: const Stream.empty(),
        foregroundMessages: const Stream.empty(),
      );
    });

    testWidgets('persists recovery before parallel, bounded network cleanup', (
      tester,
    ) async {
      final fcm = Completer<void>();
      final deletion = Completer<void>();
      when(() => messaging.deleteToken()).thenAnswer((_) {
        expectSync(prefs.getStringList('pending_fcm_clear_uids'), ['alice']);
        return fcm.future;
      });
      when(() => tokenRef.delete()).thenAnswer((_) => deletion.future);

      final cleanup = service.clearToken();
      await tester.pump();
      verify(() => messaging.deleteToken()).called(1);
      verify(() => tokenRef.delete()).called(1);
      await tester.pump(const Duration(seconds: 2));
      await cleanup;
      expect(prefs.getStringList('pending_fcm_clear_uids'), ['alice']);

      fcm.completeError(StateError('late FCM error'));
      deletion.completeError(StateError('late Firestore error'));
      await tester.pump();
      expect(prefs.getStringList('pending_fcm_clear_uids'), ['alice']);
    });

    test('clears Firestore even if FCM fails', () async {
      when(() => messaging.deleteToken()).thenThrow(StateError('FCM failed'));

      await service.clearToken();

      verify(() => tokenRef.delete()).called(1);
      expect(prefs.getStringList('pending_fcm_clear_uids'), isEmpty);
    });

    test('preserves pending cleanup for multiple accounts', () async {
      when(() => tokenRef.delete()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );

      await service.clearToken();
      when(() => user.uid).thenReturn('bob');
      await service.clearToken();

      expect(prefs.getStringList('pending_fcm_clear_uids'), ['alice', 'bob']);
    });

    test(
      'retries only the current account before registering its token',
      () async {
        await prefs.setStringList('pending_fcm_clear_uids', ['alice', 'bob']);

        await service.initialize();

        verifyInOrder([
          () => tokenRef.delete(),
          () =>
              messaging.getToken(vapidKey: null, serviceWorkerScriptPath: null),
          () => batch.commit(),
        ]);
        expect(prefs.getStringList('pending_fcm_clear_uids'), ['bob']);
      },
    );

    test('does not retry another account or a signed-out session', () async {
      await prefs.setStringList('pending_fcm_clear_uids', ['bob']);
      await service.initialize();
      when(() => auth.currentUser).thenReturn(null);
      await service.initialize();

      verifyNever(() => tokenRef.delete());
      expect(prefs.getStringList('pending_fcm_clear_uids'), ['bob']);
    });

    test('recovers the legacy pending marker', () async {
      await prefs.setString('pending_fcm_clear_uid', 'alice');

      await service.initialize();

      verify(() => tokenRef.delete()).called(1);
      expect(prefs.getString('pending_fcm_clear_uid'), isNull);
    });

    testWidgets('a late deletion does not erase a newer recovery marker', (
      tester,
    ) async {
      final deletion = Completer<void>();
      when(() => tokenRef.delete()).thenAnswer((_) => deletion.future);
      final cleanup = service.clearToken();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await cleanup;
      await prefs.setStringList('pending_fcm_clear_uids', ['alice', 'bob']);

      deletion.complete();
      await tester.pump();

      expect(prefs.getStringList('pending_fcm_clear_uids'), ['alice', 'bob']);
    });

    testWidgets('repairs registration after a late FCM revocation', (
      tester,
    ) async {
      final revocation = Completer<void>();
      when(() => messaging.deleteToken()).thenAnswer((_) => revocation.future);
      final cleanup = service.clearToken();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await cleanup;

      when(() => user.uid).thenReturn('bob');
      await service.initialize();
      verify(() => batch.commit()).called(1);

      revocation.complete();
      await tester.pump();

      verify(() => batch.commit()).called(1);
    });

    testWidgets('an offline retry is bounded and retains recovery', (
      tester,
    ) async {
      await prefs.setStringList('pending_fcm_clear_uids', ['alice']);
      final deletion = Completer<void>();
      when(() => tokenRef.delete()).thenAnswer((_) => deletion.future);
      final initialization = service.initialize();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await initialization;

      expect(prefs.getStringList('pending_fcm_clear_uids'), ['alice']);
      verify(() => batch.commit()).called(1);
      deletion.complete();
      await tester.pump();
    });

    test(
      'does not save a token whose retrieval finishes after sign-out',
      () async {
        final token = Completer<String?>();
        final requested = Completer<void>();
        when(
          () =>
              messaging.getToken(vapidKey: null, serviceWorkerScriptPath: null),
        ).thenAnswer((_) {
          requested.complete();
          return token.future;
        });
        final registration = service.saveTokenIfGranted();
        await requested.future;

        await service.clearToken();
        token.complete('old-token');
        await registration;

        verifyNever(() => batch.commit());
      },
    );
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

  test(
    'ignores a late token write denied after account deletion starts',
    () async {
      const installationId = 'abcdefghijklmnopqrstuvwx';
      SharedPreferences.setMockInitialValues({
        'push_installation_id': installationId,
      });

      final messaging = MockFirebaseMessaging();
      final firestore = MockFirebaseFirestore();
      final auth = MockFirebaseAuth();
      final settings = MockNotificationSettings();
      final user = MockUser();
      final privateUsers = MockCollectionReference();
      final pushTokens = MockCollectionReference();
      final deletionJobs = MockCollectionReference();
      final privateUserRef = MockDocumentReference();
      final tokenRef = MockDocumentReference();
      final deletionJobRef = MockDocumentReference();
      final deletionJob = MockDocumentSnapshot();
      final batch = MockWriteBatch();
      final prefs = await SharedPreferences.getInstance();

      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('alice');
      when(() => messaging.getNotificationSettings())
          .thenAnswer((_) async => settings);
      when(() => settings.authorizationStatus)
          .thenReturn(AuthorizationStatus.authorized);
      when(
        () => messaging.getToken(vapidKey: null, serviceWorkerScriptPath: null),
      ).thenAnswer((_) async => 'fcm-token');
      when(() => firestore.collection('user_private')).thenReturn(privateUsers);
      when(() => privateUsers.doc('alice')).thenReturn(privateUserRef);
      when(() => privateUserRef.collection('push_tokens'))
          .thenReturn(pushTokens);
      when(() => pushTokens.doc(installationId)).thenReturn(tokenRef);
      when(() => firestore.batch()).thenReturn(batch);
      when(() => batch.commit()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      when(() => firestore.collection('account_deletions'))
          .thenReturn(deletionJobs);
      when(() => deletionJobs.doc('alice')).thenReturn(deletionJobRef);
      when(() => deletionJobRef.get()).thenAnswer((_) async => deletionJob);
      when(() => deletionJob.exists).thenReturn(true);

      final service = NotificationService(
        messaging: messaging,
        firestore: firestore,
        auth: auth,
        prefs: prefs,
        onNotificationTapped: (_) {},
        getActiveChatId: () => null,
        tokenRefreshes: const Stream.empty(),
        foregroundMessages: const Stream.empty(),
      );

      await expectLater(service.saveTokenIfGranted(), completes);

      verify(() => batch.commit()).called(1);
      verify(() => deletionJobRef.get()).called(1);
    },
  );
}
