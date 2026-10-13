import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/session_provider.dart';
import 'package:musi_link/services/auth_service.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/music_profile_service.dart';

import '../helpers/mocks.dart';

class MockAuthService extends Mock implements AuthService {}

class MockChatService extends Mock implements ChatService {}

class MockMusicProfileService extends Mock implements MusicProfileService {}

void main() {
  late MockAuthService authService;
  late MockFirebaseAuth firebaseAuth;
  late MockChatService chatService;
  late MockMusicProfileService musicProfileService;
  late MockUserService userService;
  late MockNotificationService notifications;
  late ProviderContainer container;

  setUp(() {
    authService = MockAuthService();
    firebaseAuth = MockFirebaseAuth();
    chatService = MockChatService();
    musicProfileService = MockMusicProfileService();
    userService = MockUserService();
    notifications = MockNotificationService();
    when(() => notifications.clearLocalNotifications())
        .thenAnswer((_) async {});
    when(() => notifications.clearToken()).thenAnswer((_) async {});
    // Ejecuta las limpiezas recibidas para comprobar cuáles se solicitan.
    when(
      () => authService.signOut(cleanups: any(named: 'cleanups')),
    ).thenAnswer((invocation) async {
      final cleanups =
          invocation.namedArguments[#cleanups] as List<Future<void> Function()>;
      for (final cleanup in cleanups) {
        await cleanup();
      }
    });
    when(() => firebaseAuth.signOut()).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        firebaseAuthProvider.overrideWithValue(firebaseAuth),
        chatServiceProvider.overrideWithValue(chatService),
        musicProfileServiceProvider.overrideWithValue(musicProfileService),
        userServiceProvider.overrideWithValue(userService),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
  });

  void verifyCachesCleared() {
    verify(() => chatService.clearCache()).called(1);
    verify(() => musicProfileService.clearCache()).called(1);
    verify(() => userService.clearCache()).called(1);
  }

  group('SessionController.signOut', () {
    test('cierra la sesión y después descarta el estado', () async {
      container.read(activeChatIdProvider.notifier).setChat('chat_1');

      await container.read(sessionControllerProvider).signOut();

      verifyInOrder([
        () => authService.signOut(cleanups: any(named: 'cleanups')),
        () => chatService.clearCache(),
      ]);
      verify(() => notifications.clearLocalNotifications()).called(1);
      verify(() => notifications.clearToken()).called(1);
      verify(() => musicProfileService.clearCache()).called(1);
      verify(() => userService.clearCache()).called(1);
      expect(container.read(activeChatIdProvider), isNull);
    });

    test('si el cierre falla, propaga el error y conserva el estado', () async {
      final failure = StateError('sign-out failed');
      when(() => authService.signOut(cleanups: any(named: 'cleanups')))
          .thenThrow(failure);
      container.read(activeChatIdProvider.notifier).setChat('chat_1');

      await expectLater(
        container.read(sessionControllerProvider).signOut(),
        throwsA(same(failure)),
      );

      verifyNever(() => chatService.clearCache());
      verifyNever(() => musicProfileService.clearCache());
      verifyNever(() => userService.clearCache());
      expect(container.read(activeChatIdProvider), 'chat_1');
    });
  });

  group('SessionController.signOutAfterDeletionRequest', () {
    test('descarta el estado y no intenta borrar el token', () async {
      await container
          .read(sessionControllerProvider)
          .signOutAfterDeletionRequest();

      verifyInOrder([
        () => chatService.clearCache(),
        () => authService.signOut(cleanups: any(named: 'cleanups')),
      ]);
      verify(() => notifications.clearLocalNotifications()).called(1);
      verifyNever(() => notifications.clearToken());
      verify(() => musicProfileService.clearCache()).called(1);
      verify(() => userService.clearCache()).called(1);
      verifyNever(() => firebaseAuth.signOut());
    });

    test('recurre a Firebase Auth si falla el cierre normal', () async {
      when(() => authService.signOut(cleanups: any(named: 'cleanups')))
          .thenThrow(StateError('sign-out failed'));
      when(() => firebaseAuth.signOut()).thenThrow(StateError('offline'));

      await container
          .read(sessionControllerProvider)
          .signOutAfterDeletionRequest();

      verify(() => firebaseAuth.signOut()).called(1);
      verifyCachesCleared();
    });
  });
}
