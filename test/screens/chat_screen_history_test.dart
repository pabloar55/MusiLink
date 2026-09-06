import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/widgets/chat/message_bubble.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

void main() {
  for (final hasCache in [false, true]) {
    testWidgets('keeps history live with initial cache: $hasCache', (
      tester,
    ) async {
      final initial = StreamController<List<Message>>.broadcast();
      final recent = StreamController<List<Message>>.broadcast();
      final history = StreamController<List<Message>>.broadcast();
      final olderPage = Completer<List<Message>>();
      final relationship = StreamController<RelationshipResult>();
      final all = List.generate(
        60,
        (i) => Message(
          id: 'message-$i',
          senderId: 'current-user',
          text: 'Message $i',
          timestamp: DateTime(2026, 7, 19, 12, i),
        ),
      );
      final chatService = _MockChatService();
      final notificationService = MockNotificationService();
      final userService = MockUserService();
      final auth = MockFirebaseAuth();
      final currentUser = MockUser();
      when(() => auth.currentUser).thenReturn(currentUser);
      when(() => currentUser.uid).thenReturn('current-user');
      final deletionCheck = Completer<DateTime?>();
      when(() => chatService.getDeletedSince('chat-1'))
          .thenAnswer((_) => deletionCheck.future);
      when(() => chatService.getCachedMessages('chat-1'))
          .thenReturn(hasCache ? all.sublist(30) : null);
      when(() => chatService.getMessages('chat-1'))
          .thenAnswer((_) => initial.stream);
      when(() => chatService.getMessages('chat-1', from: all[30].timestamp))
          .thenAnswer((_) => recent.stream);
      when(() => chatService.getMessages('chat-1', from: all.first.timestamp))
          .thenAnswer((_) => history.stream);
      when(
        () =>
            chatService.loadOlderMessages('chat-1', before: all[30].timestamp),
      ).thenAnswer((_) => olderPage.future);
      when(() => chatService.markMessagesAsRead('chat-1'))
          .thenAnswer((_) async {});
      when(() => notificationService.cancelChatNotifications('chat-1'))
          .thenAnswer((_) async {});
      when(() => userService.getUser('other-user'))
          .thenAnswer((_) async => null);

      final router = GoRouter(
        initialLocation: '/chat',
        routes: [
          GoRoute(
            path: '/chat',
            builder: (_, _) => const ChatScreen(
              chatId: 'chat-1',
              otherUserName: 'Other User',
              otherUserId: 'other-user',
            ),
          ),
        ],
      );
      addTearDown(() async {
        router.dispose();
        await initial.close();
        await recent.close();
        await history.close();
        await relationship.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            chatServiceProvider.overrideWithValue(chatService),
            notificationServiceProvider.overrideWithValue(notificationService),
            userServiceProvider.overrideWithValue(userService),
            relationshipProvider('other-user')
                .overrideWith((_) => relationship.stream),
          ],
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      // A warm chat is already visible while the network check is pending.
      expect(
        find.byType(SkeletonChatMessages),
        hasCache ? findsNothing : findsOneWidget,
      );
      expect(find.text('Message 59'), hasCache ? findsOneWidget : findsNothing);
      verifyNever(() => chatService.getMessages('chat-1'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      final composerPosition = tester.getTopLeft(find.byType(TextField));
      final sendButton = find.widgetWithIcon(
        IconButton,
        LucideIcons.sendHorizontal500,
      );
      final musicButton = find.widgetWithIcon(IconButton, LucideIcons.music);
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
      expect(tester.widget<IconButton>(musicButton).onPressed, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).onSubmitted,
        isNull,
      );
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          'Draft';
      relationship.add(const RelationshipResult(RelationshipStatus.friends));
      deletionCheck.complete(null);
      await tester.pump();
      initial.add(all.sublist(30));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(TextField)), composerPosition);
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      expect(tester.widget<IconButton>(musicButton).onPressed, isNotNull);
      expect(find.text('Draft'), findsOneWidget);
      expect(initial.hasListener, isFalse);
      expect(recent.hasListener, isTrue);
      recent.add(all.sublist(30));
      await tester.pumpAndSettle();

      final list = tester.widget<ListView>(find.byType(ListView));
      final scroll = list.controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent - 50);
      await tester.pump();
      final offset = scroll.offset;
      final anchor = find.text('Message 33');
      final anchorPosition = tester.getTopLeft(anchor);

      // Updates during the request must not clear the pagination guard.
      recent.add(all.sublist(30));
      await tester.pump();
      scroll.jumpTo(offset + 1);
      scroll.jumpTo(offset);
      verify(
        () =>
            chatService.loadOlderMessages('chat-1', before: all[30].timestamp),
      ).called(1);

      olderPage.complete(all.sublist(0, 30));
      await tester.pump();
      expect(recent.hasListener, isFalse);
      expect(history.hasListener, isTrue);
      history.add(all);
      await tester.pumpAndSettle();

      expect(scroll.offset, offset);
      expect(tester.getTopLeft(anchor), anchorPosition);
      expect(
        tester
            .widget<ListView>(find.byType(ListView))
            .childrenDelegate
            .estimatedChildCount,
        60,
      );
      verifyNever(
        () => chatService.loadOlderMessages(
          'chat-1',
          before: any(named: 'before'),
        ),
      );

      // Message 28 is outside the original 30-message window.
      scroll.jumpTo(offset + 200);
      await tester.pumpAndSettle();
      final updated = List<Message>.of(all);
      updated[28] = Message(
        id: all[28].id,
        senderId: all[28].senderId,
        text: all[28].text,
        timestamp: all[28].timestamp,
        read: true,
        reactions: const {
          '👍': ['other-user'],
        },
      );
      history.add(updated);
      await tester.pumpAndSettle();
      final bubble = tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .singleWhere((bubble) => bubble.message.id == 'message-28');
      expect(bubble.message.read, isTrue);
      expect(bubble.message.reactions, {
        '👍': ['other-user'],
      });

      // Deletions replace the live window instead of preserving stale rows.
      history.add(
        updated.where((message) => message.id != 'message-28').toList(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Message 28'), findsNothing);
      expect(
        tester
            .widget<ListView>(find.byType(ListView))
            .childrenDelegate
            .estimatedChildCount,
        59,
      );

      // New arrivals keep the oldest loaded message in the subscribed window.
      final newest = Message(
        id: 'message-60',
        senderId: 'other-user',
        text: 'New arrival',
        timestamp: DateTime(2026, 7, 19, 13),
      );
      history.add([
        ...updated.where((message) => message.id != 'message-28'),
        newest,
      ]);
      await tester.pumpAndSettle();
      expect(find.text('New arrival'), findsOneWidget);
      expect(history.hasListener, isTrue);
      when(
        () => chatService.loadOlderMessages(
          'chat-1',
          before: all.first.timestamp,
        ),
      ).thenAnswer((_) async => []);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Message 0'), findsOneWidget);
      verify(
        () => chatService.loadOlderMessages(
          'chat-1',
          before: all.first.timestamp,
        ),
      ).called(1);
      scroll.jumpTo(scroll.offset - 1);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      verifyNever(
        () => chatService.loadOlderMessages(
          'chat-1',
          before: any(named: 'before'),
        ),
      );

      relationship.add(const RelationshipResult(RelationshipStatus.blocked));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(sendButton, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(history.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
