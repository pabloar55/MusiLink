// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/push_token_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockNotificationSettings extends Mock implements NotificationSettings {}

class MockUser extends Mock implements User {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockWriteBatch extends Mock implements WriteBatch {}

MockDocumentSnapshot mockPublishedProfile(MockFirebaseFirestore firestore) {
  final users = MockCollectionReference();
  final profileRef = MockDocumentReference();
  final profile = MockDocumentSnapshot();
  when(() => firestore.collection('users')).thenReturn(users);
  when(() => users.doc(any())).thenReturn(profileRef);
  when(() => profileRef.get(const GetOptions(source: Source.server)))
      .thenAnswer((_) async => profile);
  when(() => profile.exists).thenReturn(true);
  when(() => profile.data()).thenReturn({'username': 'alice_name'});
  return profile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('token lifecycle', () {
    late MockFirebaseMessaging messaging;
    late MockFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockUser user;
    late MockDocumentReference tokenRef;
    late MockNotificationSettings settings;
    late MockWriteBatch batch;
    late MockDocumentSnapshot profile;
    late SharedPreferences prefs;
    late PushTokenRegistry registry;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'push_installation_id': 'installation',
      });
      messaging = MockFirebaseMessaging();
      firestore = MockFirebaseFirestore();
      profile = mockPublishedProfile(firestore);
      auth = MockFirebaseAuth();
      user = MockUser();
      tokenRef = MockDocumentReference();
      settings = MockNotificationSettings();
      batch = MockWriteBatch();
      final privateUsers = MockCollectionReference();
      final privateUser = MockDocumentReference();
      final tokens = MockCollectionReference();
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

      registry = PushTokenRegistry(
        messaging: messaging,
        firestore: firestore,
        auth: auth,
        prefs: prefs,
      );
    });

    test(
      'defers tokens during onboarding and retries after publication',
      () async {
        when(() => profile.exists).thenReturn(false);
        when(() => profile.data()).thenReturn(null);

        await registry.restoreSession();
        await registry.saveTokenIfGranted();

        verifyNever(() => batch.commit());
        verifyNever(
          () =>
              messaging.getToken(vapidKey: null, serviceWorkerScriptPath: null),
        );

        when(() => profile.exists).thenReturn(true);
        when(() => profile.data()).thenReturn({'username': 'alice_name'});
        await registry.saveTokenIfGranted();

        verify(() => batch.commit()).called(1);
      },
    );

    test('does not register tokens for an anonymized profile', () async {
      when(() => profile.data()).thenReturn({'username': 'deleted_user'});

      await registry.saveTokenIfGranted();

      verifyNever(() => batch.commit());
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

      final cleanup = registry.clearToken();
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

      await registry.clearToken();

      verify(() => tokenRef.delete()).called(1);
      expect(prefs.getStringList('pending_fcm_clear_uids'), isEmpty);
    });

    test('preserves pending cleanup for multiple accounts', () async {
      when(() => tokenRef.delete()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );

      await registry.clearToken();
      when(() => user.uid).thenReturn('bob');
      await registry.clearToken();

      expect(prefs.getStringList('pending_fcm_clear_uids'), ['alice', 'bob']);
    });

    test(
      'retries only the current account before registering its token',
      () async {
        await prefs.setStringList('pending_fcm_clear_uids', ['alice', 'bob']);

        await registry.restoreSession();

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
      await registry.restoreSession();
      when(() => auth.currentUser).thenReturn(null);
      await registry.restoreSession();

      verifyNever(() => tokenRef.delete());
      expect(prefs.getStringList('pending_fcm_clear_uids'), ['bob']);
    });

    test('recovers the legacy pending marker', () async {
      await prefs.setString('pending_fcm_clear_uid', 'alice');

      await registry.restoreSession();

      verify(() => tokenRef.delete()).called(1);
      expect(prefs.getString('pending_fcm_clear_uid'), isNull);
    });

    testWidgets('a late deletion does not erase a newer recovery marker', (
      tester,
    ) async {
      final deletion = Completer<void>();
      when(() => tokenRef.delete()).thenAnswer((_) => deletion.future);
      final cleanup = registry.clearToken();
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
      final cleanup = registry.clearToken();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await cleanup;

      when(() => user.uid).thenReturn('bob');
      registry.startSession();
      await registry.restoreSession();
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
      final restoration = registry.restoreSession();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await restoration;

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
        final registration = registry.saveTokenIfGranted();
        await requested.future;

        await registry.clearToken();
        token.complete('old-token');
        await registration;

        verifyNever(() => batch.commit());
      },
    );

    test(
      'a session that ended registers nothing until a new one starts',
      () async {
        registry.endSession();
        await registry.saveTokenIfGranted();
        expect(registry.isSessionActive, isFalse);
        verifyNever(() => batch.commit());

        registry.startSession();
        await registry.saveTokenIfGranted();
        expect(registry.isSessionActive, isTrue);
        verify(() => batch.commit()).called(1);
      },
    );
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

      mockPublishedProfile(firestore);
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

      final registry = PushTokenRegistry(
        messaging: messaging,
        firestore: firestore,
        auth: auth,
        prefs: prefs,
      );

      await expectLater(registry.saveTokenIfGranted(), completes);

      verify(() => batch.commit()).called(1);
      verify(() => deletionJobRef.get()).called(1);
    },
  );
}
