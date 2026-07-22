import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/router/app_route_observer.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

void main() {
  testWidgets('does not mark messages read while profile covers the chat', (
    tester,
  ) async {
    final messages = StreamController<List<Message>>.broadcast();
    final chatService = _MockChatService();
    final notificationService = MockNotificationService();
    final userService = MockUserService();
    final auth = MockFirebaseAuth();
    final currentUser = MockUser();

    when(() => auth.currentUser).thenReturn(currentUser);
    when(() => currentUser.uid).thenReturn('current-user');
    when(
      () => chatService.getDeletedSince('chat-1'),
    ).thenAnswer((_) async => null);
    when(
      () => chatService.getMessages('chat-1'),
    ).thenAnswer((_) => messages.stream);
    when(
      () => chatService.markMessagesAsRead('chat-1'),
    ).thenAnswer((_) async {});
    when(
      () => notificationService.cancelChatNotifications('chat-1'),
    ).thenAnswer((_) async {});
    when(() => userService.getUser('other-user')).thenAnswer((_) async => null);

    final router = GoRouter(
      initialLocation: '/chat',
      observers: [appRouteObserver],
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => const ChatScreen(
            chatId: 'chat-1',
            otherUserName: 'Other User',
            otherUserId: 'other-user',
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(body: Text('Profile')),
        ),
      ],
    );
    addTearDown(() async {
      router.dispose();
      await messages.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          chatServiceProvider.overrideWithValue(chatService),
          notificationServiceProvider.overrideWithValue(notificationService),
          userServiceProvider.overrideWithValue(userService),
          relationshipProvider('other-user').overrideWith(
            (_) => Stream.value(
              const RelationshipResult(RelationshipStatus.friends),
            ),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    clearInteractions(chatService);

    unawaited(router.push('/profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final firstMessage = Message(
      id: 'message-1',
      senderId: 'other-user',
      text: 'First',
      timestamp: DateTime(2026, 7, 19, 12),
    );
    messages.add([firstMessage]);
    await tester.pump();

    verifyNever(() => chatService.markMessagesAsRead('chat-1'));

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    verify(() => chatService.markMessagesAsRead('chat-1')).called(1);

    final sameDayMessage = Message(
      id: 'message-2',
      senderId: 'current-user',
      text: 'Same day',
      timestamp: DateTime(2026, 7, 19, 18),
    );
    final nextDayMessage = Message(
      id: 'message-3',
      senderId: 'other-user',
      text: 'Next day',
      timestamp: DateTime(2026, 7, 20, 9),
    );
    messages.add([firstMessage, sameDayMessage, nextDayMessage]);
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-date-2026-7-19')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-date-2026-7-20')), findsOneWidget);
  });
}
