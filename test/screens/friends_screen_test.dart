import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/friend_request.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/screens/friends_screen.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/widgets/friends/friend_tile.dart';

class _MockFriendService extends Mock implements FriendService {}

class _MockUserService extends Mock implements UserService {}

const _sender = AppUser(uid: 'sender_uid', displayName: 'Bob', username: 'bob');

final _request = FriendRequest(
  id: 'sender_uid_current_uid',
  senderId: 'sender_uid',
  receiverId: 'current_uid',
  status: FriendRequestStatus.pending,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Widget _app({
  required FriendService friendService,
  required UserService userService,
  required Stream<List<FriendRequest>> receivedRequests,
  required Stream<List<String>> friends,
}) {
  return ProviderScope(
    overrides: [
      friendServiceProvider.overrideWithValue(friendService),
      userServiceProvider.overrideWithValue(userService),
      receivedRequestsProvider.overrideWith((_) => receivedRequests),
      sentRequestsProvider.overrideWith(
        (_) => Stream.value(const <FriendRequest>[]),
      ),
      friendsStreamProvider.overrideWith((_) => friends),
    ],
    child: const MaterialApp(
      locale: Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FriendsScreen(),
    ),
  );
}

void main() {
  late _MockFriendService friendService;
  late _MockUserService userService;

  setUp(() {
    friendService = _MockFriendService();
    userService = _MockUserService();
    when(() => userService.getUser('sender_uid'))
        .thenAnswer((_) async => _sender);
    when(() => userService.getUsersByIds(any()))
        .thenAnswer((_) async => const [_sender]);
  });

  testWidgets('acepta de forma optimista y revierte la UI si falla', (
    tester,
  ) async {
    final acceptance = Completer<void>();
    when(
      () => friendService.acceptRequest('sender_uid_current_uid', 'sender_uid'),
    ).thenAnswer((_) => acceptance.future);

    await tester.pumpWidget(
      _app(
        friendService: friendService,
        userService: userService,
        receivedRequests: Stream.value([_request]),
        friends: Stream.value(const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Aceptar'), findsOneWidget);
    expect(find.byType(FriendTile), findsNothing);

    await tester.tap(find.byTooltip('Aceptar'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Aceptar'), findsNothing);
    expect(find.byType(FriendTile), findsOneWidget);
    verify(
      () => friendService.acceptRequest('sender_uid_current_uid', 'sender_uid'),
    ).called(1);

    acceptance.completeError(Exception('accept failed'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Aceptar'), findsOneWidget);
    expect(find.byType(FriendTile), findsNothing);
    expect(find.text('Algo salió mal. Inténtalo de nuevo.'), findsOneWidget);
  });

  testWidgets('retira el overlay cuando ambos streams confirman la amistad', (
    tester,
  ) async {
    final requestsController = StreamController<List<FriendRequest>>();
    final friendsController = StreamController<List<String>>();
    addTearDown(requestsController.close);
    addTearDown(friendsController.close);
    when(
      () => friendService.acceptRequest('sender_uid_current_uid', 'sender_uid'),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      _app(
        friendService: friendService,
        userService: userService,
        receivedRequests: requestsController.stream,
        friends: friendsController.stream,
      ),
    );
    requestsController.add([_request]);
    friendsController.add(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.byType(FriendTile), findsOneWidget);

    requestsController.add(const []);
    friendsController.add(const ['sender_uid']);
    await tester.pumpAndSettle();

    // A later authoritative removal must not be masked by stale optimistic state.
    friendsController.add(const []);
    await tester.pumpAndSettle();

    expect(find.byType(FriendTile), findsNothing);
  });
}
