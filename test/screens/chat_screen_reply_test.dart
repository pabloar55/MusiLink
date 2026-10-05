import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/message_reply.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/utils/app_localizations_delegates.dart';
import 'package:musi_link/widgets/chat/reply_quote.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

void main() {
  testWidgets(
    'swiping a message right quotes it in the composer and sends it as a reply',
    (tester) async {
      final events = StreamController<List<Message>>.broadcast();
      final service = _MockChatService();
      final auth = MockFirebaseAuth();
      final user = MockUser();
      final notifications = MockNotificationService();
      final users = MockUserService();
      final serverTime = DateTime(2026);
      final incoming = Message(
        id: 'incoming',
        senderId: 'other-user',
        text: 'Received',
        timestamp: serverTime,
        replyTo: const MessageReply(
          messageId: 'original',
          senderId: 'current-user',
          text: 'Original',
        ),
      );
      final pending = Message(
        id: 'pending',
        senderId: 'current-user',
        text: 'Unconfirmed',
        timestamp: DateTime(2099),
        isPending: true,
      );
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('current-user');
      when(() => service.getDeletedSince('chat-1'))
          .thenAnswer((_) async => null);
      when(() => service.getMessages('chat-1'))
          .thenAnswer((_) => events.stream);
      when(() => service.getMessages('chat-1', from: serverTime))
          .thenAnswer((_) => events.stream);
      when(() => service.markMessagesAsRead('chat-1')).thenAnswer((_) async {});
      when(
        () => service.sendMessage(
          'chat-1',
          any(),
          replyTo: any(named: 'replyTo'),
        ),
      ).thenAnswer((_) async {});
      when(() => notifications.cancelChatNotifications('chat-1'))
          .thenAnswer((_) async {});
      when(() => users.getUser('other-user')).thenAnswer((_) async => null);
      final router = GoRouter(
        initialLocation: '/chat',
        routes: [
          GoRoute(
            path: '/chat',
            builder: (_, _) => const ChatScreen(
              chatId: 'chat-1',
              otherUserName: 'Other',
              otherUserId: 'other-user',
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            chatServiceProvider.overrideWithValue(service),
            notificationServiceProvider.overrideWithValue(notifications),
            userServiceProvider.overrideWithValue(users),
            relationshipProvider('other-user').overrideWith(
              (_) => Stream.value(
                const RelationshipResult(RelationshipStatus.friends),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump();
      events.add([incoming, pending]);
      await tester.pumpAndSettle();

      // The stored quote names its author inside the bubble.
      expect(find.widgetWithText(ReplyQuote, 'You'), findsOneWidget);
      expect(find.widgetWithText(ReplyQuote, 'Original'), findsOneWidget);

      // Neither a short swipe nor an unconfirmed message starts a reply.
      await tester.drag(find.text('Received'), const Offset(30, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Unconfirmed'), const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cancel reply'), findsNothing);

      await tester.drag(find.text('Received'), const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ReplyQuote, 'Received'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ReplyQuote, 'Received'), findsNothing);

      await tester.drag(find.text('Received'), const Offset(150, 0));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Answer');
      await tester.tap(
        find.widgetWithIcon(IconButton, LucideIcons.sendHorizontal500),
      );
      await tester.pumpAndSettle();
      final replyTo = verify(
        () => service.sendMessage(
          'chat-1',
          'Answer',
          replyTo: captureAny(named: 'replyTo'),
        ),
      ).captured.single;
      expect(replyTo, same(incoming));
      expect(find.byTooltip('Cancel reply'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await events.close();
    },
  );
}
