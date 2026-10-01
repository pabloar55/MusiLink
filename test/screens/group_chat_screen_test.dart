import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/screens/create_group_chat_screen.dart';
import 'package:musi_link/screens/group_chat_screen.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/utils/app_localizations_delegates.dart';

import '../helpers/mocks.dart';

class _MockChatService extends Mock implements ChatService {}

Chat _group({
  String id = 'group-1',
  String name = 'Music friends',
  bool isGroup = true,
  List<String> participants = const ['current-user', 'other-user'],
}) => Chat(
  id: id,
  name: name,
  isGroup: isGroup,
  participants: participants,
  lastMessageTime: DateTime(2026),
  createdAt: DateTime(2026),
);

Future<_MockChatService> _openGroup(
  WidgetTester tester,
  Stream<Chat?> groups, {
  Chat? initialGroup,
}) async {
  final service = _MockChatService();
  final auth = MockFirebaseAuth();
  final user = MockUser();
  final notifications = MockNotificationService();
  final users = MockUserService();
  when(() => users.getUser(any())).thenAnswer((_) async => null);
  when(() => auth.currentUser).thenReturn(user);
  when(() => user.uid).thenReturn('current-user');
  when(() => service.watchChat('group-1')).thenAnswer((_) => groups);
  when(() => service.getCachedMessages('group-1')).thenReturn([]);
  when(() => service.getCachedHistory('group-1'))
      .thenReturn((since: null, messages: <Message>[]));
  when(() => service.getDeletedSince('group-1')).thenAnswer((_) async => null);
  when(() => service.getMessages('group-1'))
      .thenAnswer((_) => const Stream<List<Message>>.empty());
  when(() => notifications.cancelChatNotifications('group-1'))
      .thenAnswer((_) async {});
  final router = GoRouter(
    initialLocation: '/group-chat/group-1',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('Messages')),
      GoRoute(
        path: '/group-chat/:chatId',
        builder: (_, state) => GroupChatScreen(
          chatId: state.pathParameters['chatId']!,
          initialGroup: initialGroup,
        ),
        routes: [
          GoRoute(
            path: 'add-members',
            builder: (_, state) =>
                AddGroupMembersScreen(chatId: state.pathParameters['chatId']!),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        chatServiceProvider.overrideWithValue(service),
        notificationServiceProvider.overrideWithValue(notifications),
        userServiceProvider.overrideWithValue(users),
        friendProfilesStreamProvider.overrideWith(
          (_) => Stream.value(const [
            AppUser(uid: 'other-user', displayName: 'Already Here'),
            AppUser(uid: 'new-friend', displayName: 'New Friend'),
            AppUser(uid: 'second-friend', displayName: 'Second Friend'),
          ]),
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
  return service;
}

void main() {
  late StreamController<Chat?> groups;
  setUp(() => groups = StreamController<Chat?>());
  tearDown(() => groups.close());

  testWidgets('opens immediately and updates without losing the draft', (
    tester,
  ) async {
    await _openGroup(tester, groups.stream, initialGroup: _group());
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(groups.hasListener, isTrue);
    await tester.enterText(find.byType(TextField), 'My draft');

    groups.add(_group(name: 'Updated group'));
    await tester.pumpAndSettle();
    expect(find.text('Updated group'), findsOneWidget);
    expect(find.text('Music friends'), findsNothing);
    expect(find.text('My draft'), findsOneWidget);
  });

  testWidgets('leaving requires confirmation and returns to the chat list', (
    tester,
  ) async {
    final service = await _openGroup(
      tester,
      groups.stream,
      initialGroup: _group(),
    );
    when(() => service.leaveGroupChat('group-1')).thenAnswer((_) async {});

    await tester.tap(find.text('Music friends'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Leave group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this group?'), findsOneWidget);
    verifyNever(() => service.leaveGroupChat(any()));

    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    verify(() => service.leaveGroupChat('group-1')).called(1);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('Messages'), findsOneWidget);
  });

  testWidgets('adding members offers only friends outside the group', (
    tester,
  ) async {
    final service = await _openGroup(
      tester,
      groups.stream,
      initialGroup: _group(),
    );
    when(() => service.addGroupMembers('group-1', ['new-friend']))
        .thenAnswer((_) async {});
    groups.add(_group());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Music friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add members'));
    await tester.pumpAndSettle();
    expect(find.byType(AddGroupMembersScreen), findsOneWidget);
    expect(find.text('New Friend'), findsOneWidget);
    expect(find.text('Already Here'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('New Friend'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    verify(() => service.addGroupMembers('group-1', ['new-friend'])).called(1);
    expect(find.byType(AddGroupMembersScreen), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('a selected friend added by someone else frees their seat', (
    tester,
  ) async {
    final members = [
      'current-user',
      for (var index = 1; index < 18; index += 1) 'member-$index',
    ];
    final service = await _openGroup(
      tester,
      groups.stream,
      initialGroup: _group(participants: members),
    );
    when(() => service.addGroupMembers('group-1', ['second-friend']))
        .thenAnswer((_) async {});
    groups.add(_group(participants: members));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Friend'));
    await tester.pumpAndSettle();

    // Otro miembro añade al amigo seleccionado: queda una única plaza libre.
    groups.add(_group(participants: [...members, 'new-friend']));
    await tester.pumpAndSettle();
    expect(find.text('New Friend'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Second Friend'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    verify(() => service.addGroupMembers('group-1', ['second-friend']))
        .called(1);
  });

  testWidgets('a direct link waits for verified group data', (tester) async {
    await _openGroup(tester, groups.stream);
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    groups.add(_group());
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final invalid in [
    _group(id: 'another-group'),
    _group(isGroup: false),
    _group(participants: ['other-user']),
  ]) {
    testWidgets('ignores invalid initial group data: ${invalid.id}, '
        '${invalid.isGroup}, ${invalid.participants}', (tester) async {
      await _openGroup(tester, groups.stream, initialGroup: invalid);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      groups.add(_group());
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  }

  for (final outcome in ['deleted', 'removed', 'error', 'error-after-data']) {
    testWidgets('discards initial membership when $outcome', (tester) async {
      await _openGroup(tester, groups.stream, initialGroup: _group());
      expect(find.byType(ChatScreen), findsOneWidget);
      if (outcome == 'error-after-data') {
        groups.add(_group());
        await tester.pumpAndSettle();
      }
      if (outcome.startsWith('error')) {
        groups.addError(StateError('Permission denied'));
      } else {
        groups.add(
          outcome == 'deleted' ? null : _group(participants: ['other-user']),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final context = tester.element(find.byType(GroupChatScreen));
      expect(
        find.text(AppLocalizations.of(context)!.groupChatUnavailable),
        findsOneWidget,
      );
    });
  }
}
