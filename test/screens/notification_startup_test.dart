import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/main.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

class _MockMusicProfileService extends Mock implements MusicProfileService {}

void main() {
  testWidgets('handles notification taps when launched directly into a chat', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = StreamController<User?>();
    final user = MockUser();
    when(() => user.uid).thenReturn('alice');
    final notifications = MockNotificationService();
    when(notifications.initialize).thenAnswer((_) async {});
    final chatService = _MockChatService();
    final musicProfileService = _MockMusicProfileService();
    final userService = MockUserService();
    final router = GoRouter(
      initialLocation: '/chat?chatId=first',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, state) => Scaffold(
            body: Text('Chat ${state.uri.queryParameters['chatId']}'),
          ),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        goRouterProvider.overrideWithValue(router),
        authStateProvider.overrideWith((_) => auth.stream),
        notificationServiceProvider.overrideWithValue(notifications),
        chatServiceProvider.overrideWithValue(chatService),
        musicProfileServiceProvider.overrideWithValue(musicProfileService),
        userServiceProvider.overrideWithValue(userService),
      ],
    );
    addTearDown(() async {
      router.dispose();
      container.dispose();
      await auth.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MainApp()),
    );
    auth.add(user);
    await tester.pumpAndSettle();
    expect(find.text('Chat first'), findsOneWidget);
    verify(notifications.initialize).called(1);

    const data = {
      'type': 'new_message',
      'chatId': 'second',
      'otherUserId': 'bob',
    };
    container.read(pendingNotificationProvider.notifier).setValue(data);
    await tester.pumpAndSettle();
    expect(find.text('Chat second'), findsOneWidget);
    expect(container.read(pendingNotificationProvider), isNull);
    // Receiving the same tap again must not push a duplicate conversation.
    container.read(pendingNotificationProvider.notifier).setValue(data);
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Chat first'), findsOneWidget);
    auth.add(null);
    await tester.pumpAndSettle();
    // Una sesión que termina sin pasar por la app descarta todas las cachés.
    verify(chatService.clearCache).called(1);
    verify(musicProfileService.clearCache).called(1);
    verify(userService.clearCache).called(1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
