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
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/utils/app_localizations_delegates.dart';
import 'package:musi_link/widgets/chat/reply_quote.dart';
import 'package:musi_link/widgets/chat/track_search_sheet.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

final _serverTime = DateTime(2026);

Message _incoming(String id, String text, {MessageReply? replyTo}) => Message(
  id: id,
  senderId: 'other-user',
  text: text,
  timestamp: _serverTime,
  replyTo: replyTo,
);

/// Opens a direct chat showing [messages] and returns its mocked service.
Future<_MockChatService> _pumpChat(
  WidgetTester tester,
  List<Message> messages, {
  StreamController<List<Message>>? history,
}) async {
  final events = history ?? StreamController<List<Message>>.broadcast();
  final service = _MockChatService();
  final auth = MockFirebaseAuth();
  final user = MockUser();
  final notifications = MockNotificationService();
  final users = MockUserService();
  when(() => auth.currentUser).thenReturn(user);
  when(() => user.uid).thenReturn('current-user');
  when(() => service.getDeletedSince('chat-1')).thenAnswer((_) async => null);
  when(() => service.getMessages('chat-1', from: any(named: 'from')))
      .thenAnswer((_) => events.stream);
  when(() => service.markMessagesAsRead('chat-1')).thenAnswer((_) async {});
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await events.close();
  });
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
  events.add(messages);
  await tester.pumpAndSettle();
  return service;
}

Future<void> _swipe(WidgetTester tester, String text, [double dx = 150]) async {
  await tester.drag(find.text(text), Offset(dx, 0));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(
    find.widgetWithIcon(IconButton, LucideIcons.sendHorizontal500),
  );
  await tester.pumpAndSettle();
}

/// Fails the pending send and waits for its error notice to leave the screen.
Future<void> _fail(WidgetTester tester, Completer<void> request) async {
  request.completeError(Exception('offline'));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsOneWidget);
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

String _draftText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

/// The quote above the composer, identified by its discard button.
Finder _draftQuote(String text) => find.ancestor(
  of: find.byTooltip('Cancel reply'),
  matching: find.widgetWithText(ReplyQuote, text),
);

/// A conversation long enough for its first messages to be off screen, ending
/// with a reply that quotes [quoted].
List<Message> _longChat(MessageReply quoted) => [
  for (var i = 0; i < 60; i++)
    Message(
      id: 'm$i',
      senderId: 'other-user',
      text: 'Message $i',
      timestamp: _serverTime.add(Duration(minutes: i)),
    ),
  Message(
    id: 'answer',
    senderId: 'other-user',
    text: 'Answer',
    timestamp: _serverTime.add(const Duration(hours: 2)),
    replyTo: quoted,
  ),
];

bool _isOnScreen(WidgetTester tester, String text) {
  final list = tester.getRect(find.byType(ListView));
  return find.text(text).evaluate().isNotEmpty &&
      list.contains(tester.getCenter(find.text(text)));
}

bool _isHighlighted(WidgetTester tester, String text) {
  final row = tester.widget<AnimatedContainer>(
    find
        .ancestor(of: find.text(text), matching: find.byType(AnimatedContainer))
        .first,
  );
  return (row.decoration! as BoxDecoration).color!.a > 0;
}

void main() {
  testWidgets(
    'swiping a message right quotes it in the composer and sends it as a reply',
    (tester) async {
      final incoming = _incoming(
        'incoming',
        'Received',
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
      final service = await _pumpChat(tester, [incoming, pending]);
      when(
        () => service.sendMessage(
          'chat-1',
          any(),
          replyTo: any(named: 'replyTo'),
        ),
      ).thenAnswer((_) async {});

      // The stored quote names its author inside the bubble.
      expect(find.widgetWithText(ReplyQuote, 'You'), findsOneWidget);
      expect(find.widgetWithText(ReplyQuote, 'Original'), findsOneWidget);

      // Neither a short swipe nor an unconfirmed message starts a reply.
      await _swipe(tester, 'Received', 30);
      await _swipe(tester, 'Unconfirmed');
      expect(find.byTooltip('Cancel reply'), findsNothing);

      await _swipe(tester, 'Received');
      expect(_draftQuote('Received'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel reply'));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyQuote), findsOneWidget);

      await _swipe(tester, 'Received');
      await _send(tester, 'Answer');
      final replyTo = verify(
        () => service.sendMessage(
          'chat-1',
          'Answer',
          replyTo: captureAny(named: 'replyTo'),
        ),
      ).captured.single;
      expect(replyTo, same(incoming));
      expect(find.byTooltip('Cancel reply'), findsNothing);
    },
  );

  testWidgets('a failed send restores its text and quote only as a whole', (
    tester,
  ) async {
    final service = await _pumpChat(tester, [
      _incoming('first', 'First'),
      _incoming('second', 'Second'),
    ]);
    var request = Completer<void>();
    when(
      () =>
          service.sendMessage('chat-1', any(), replyTo: any(named: 'replyTo')),
    ).thenAnswer((_) => request.future);

    // Untouched composer: the failed reply comes back complete.
    await _swipe(tester, 'First');
    await _send(tester, 'Answer');
    await _fail(tester, request);
    expect(_draftText(tester), 'Answer');
    expect(_draftQuote('First'), findsOneWidget);

    // A late failure must not pair the old text with a newer quote.
    request = Completer<void>();
    await _send(tester, 'Answer');
    await _swipe(tester, 'Second');
    await _fail(tester, request);
    expect(_draftText(tester), isEmpty);
    expect(_draftQuote('Second'), findsOneWidget);
    expect(_draftQuote('First'), findsNothing);
  });

  testWidgets('a failed song keeps the quote it was replying to', (
    tester,
  ) async {
    final service = await _pumpChat(tester, [
      _incoming('first', 'First'),
      _incoming('second', 'Second'),
    ]);
    const track = Track(title: 'Song', artist: 'Artist', imageUrl: '');
    var request = Completer<void>();
    when(
      () => service.sendTrackMessage(
        'chat-1',
        track,
        replyTo: any(named: 'replyTo'),
      ),
    ).thenAnswer((_) => request.future);
    Future<void> shareSong() async {
      await tester.tap(find.byTooltip('Share song'));
      await tester.pumpAndSettle();
      tester
          .widget<TrackSearchSheet>(find.byType(TrackSearchSheet))
          .onTrackSelected(track);
      await tester.pumpAndSettle();
    }

    await _swipe(tester, 'First');
    await tester.enterText(find.byType(TextField), 'Half written');
    await shareSong();
    expect(find.byTooltip('Cancel reply'), findsNothing);
    await _fail(tester, request);
    expect(_draftQuote('First'), findsOneWidget);
    expect(_draftText(tester), 'Half written');

    // Retrying sends the song as the same reply.
    request = Completer<void>();
    await shareSong();
    final replies = verify(
      () => service.sendTrackMessage(
        'chat-1',
        track,
        replyTo: captureAny(named: 'replyTo'),
      ),
    ).captured;
    expect(replies.map((reply) => (reply as Message).id), ['first', 'first']);

    // A newer quote is not replaced when that retry fails late.
    await _swipe(tester, 'Second');
    await _fail(tester, request);
    expect(_draftQuote('Second'), findsOneWidget);
    expect(_draftQuote('First'), findsNothing);
  });

  testWidgets('tapping a quote scrolls to the original message', (
    tester,
  ) async {
    final service = await _pumpChat(
      tester,
      _longChat(
        const MessageReply(
          messageId: 'm0',
          senderId: 'other-user',
          text: 'Quoted',
        ),
      ),
    );
    expect(_isOnScreen(tester, 'Message 0'), isFalse);

    await tester.tap(find.widgetWithText(ReplyQuote, 'Quoted'));
    await tester.pumpAndSettle();
    expect(_isOnScreen(tester, 'Message 0'), isTrue);
    expect(_isHighlighted(tester, 'Message 0'), isTrue);
    verifyNever(() => service.getMessage(any(), any()));

    // The highlight is only a brief cue.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_isHighlighted(tester, 'Message 0'), isFalse);
  });

  testWidgets('a quote from older history loads it before scrolling', (
    tester,
  ) async {
    final history = StreamController<List<Message>>.broadcast();
    final original = Message(
      id: 'old',
      senderId: 'other-user',
      text: 'Long ago',
      timestamp: _serverTime.subtract(const Duration(days: 30)),
    );
    final loaded = _longChat(
      const MessageReply(
        messageId: 'old',
        senderId: 'other-user',
        text: 'Quoted',
      ),
    );
    final service = await _pumpChat(tester, loaded, history: history);
    when(() => service.getMessage('chat-1', 'old'))
        .thenAnswer((_) async => original);

    await tester.tap(find.widgetWithText(ReplyQuote, 'Quoted'));
    await tester.pump();
    verify(() => service.getMessages('chat-1', from: original.timestamp))
        .called(1);
    history.add([original, ...loaded]);
    await tester.pumpAndSettle();
    expect(_isOnScreen(tester, 'Long ago'), isTrue);
    expect(_isHighlighted(tester, 'Long ago'), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('a quote whose original is gone says so and stays in place', (
    tester,
  ) async {
    final service = await _pumpChat(
      tester,
      _longChat(
        const MessageReply(
          messageId: 'gone',
          senderId: 'other-user',
          text: 'Quoted',
        ),
      ),
    );
    when(() => service.getMessage('chat-1', 'gone'))
        .thenAnswer((_) async => null);

    await tester.tap(find.widgetWithText(ReplyQuote, 'Quoted'));
    await tester.pumpAndSettle();
    expect(
      find.text('The original message is no longer available.'),
      findsOneWidget,
    );
    expect(_isOnScreen(tester, 'Answer'), isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
