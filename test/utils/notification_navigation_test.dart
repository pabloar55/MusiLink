import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/utils/notification_navigation.dart';

void main() {
  group('notificationLocationFromData', () {
    test('routes friend requests to the friends tab', () {
      expect(
        notificationLocationFromData(const {'type': 'friend_request'}),
        '/?tab=friends',
      );
    });

    test('builds a chat location from a message notification', () {
      expect(
        notificationLocationFromData(const {
          'type': 'new_message',
          'chatId': 'chat-1',
          'otherUserId': 'user-2',
          'otherUserName': 'User Two',
        }),
        '/chat?chatId=chat-1&otherUserId=user-2&otherUserName=User+Two',
      );
    });
  });

  testWidgets('defers router navigation triggered during build', (
    tester,
  ) async {
    var notificationHandled = false;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            if (!notificationHandled) {
              notificationHandled = true;
              handleNotificationNavigation(const {
                'type': 'friend_request',
              }, context);
            }
            return const SizedBox();
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/?tab=friends',
    );
  });
}
