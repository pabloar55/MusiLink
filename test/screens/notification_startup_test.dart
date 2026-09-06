import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

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
    verify(chatService.clearCache).called(1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
