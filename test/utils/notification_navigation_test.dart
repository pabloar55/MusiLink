import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/notification_navigation.dart';

void main() {
  group('notificationLocationFromData', () {
    test('routes friend requests to the friends tab', () {
      expect(
        notificationLocationFromData(const {'type': 'friend_request'}),
        '/?tab=friends',
      );
    });

    test('routes an expired daily song to the daily-song tab', () {
      expect(
        notificationLocationFromData(const {'type': 'daily_song_expired'}),
        '/?tab=daily-song',
      );
    });

    test('routes daily song likes to the daily-song tab', () {
      expect(
        notificationLocationFromData(const {'type': 'daily_song_liked'}),
        '/?tab=daily-song',
      );
    });

    test('routes the friend digest to the daily-song tab', () {
      expect(
        notificationLocationFromData(const {'type': 'friend_digest'}),
        '/?tab=daily-song',
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

  group('launchLocation', () {
    test('prefers the notification over the web hash', () {
      expect(
        launchLocation(
          notificationLocation: '/?tab=friends',
          webFragment: '/u/someone',
        ),
        '/?tab=friends',
      );
    });

    test('uses the web hash only when it is a route', () {
      expect(launchLocation(webFragment: '/u/someone'), '/u/someone');
      expect(launchLocation(webFragment: 'access_token=x'), isNull);
      expect(launchLocation(), isNull);
    });
  });

  group('directChatIdOf', () {
    test('returns the chat id of a direct chat location', () {
      expect(directChatIdOf('/chat?chatId=c1&otherUserId=u2'), 'c1');
    });

    test('ignores group chats and other locations', () {
      expect(directChatIdOf('/group-chat/g1'), isNull);
      expect(directChatIdOf('/?tab=friends'), isNull);
      expect(directChatIdOf(null), isNull);
    });
  });

  group('notificationNavigation', () {
    NotificationNavigation navigate(String current, String target) =>
        notificationNavigation(
          current: Uri.parse(current),
          target: Uri.parse(target),
        );

    test('stays on the direct chat that is already open', () {
      expect(
        navigate(
          '/chat?chatId=c1&otherUserId=u2',
          '/chat?chatId=c1&otherUserId=u2&otherUserName=U',
        ),
        NotificationNavigation.stay,
      );
    });

    test('pushes another direct chat over the current screen', () {
      expect(
        navigate(
          '/chat?chatId=c1&otherUserId=u2',
          '/chat?chatId=c2&otherUserId=u3',
        ),
        NotificationNavigation.push,
      );
      expect(
        navigate('/?tab=messages', '/chat?chatId=c1&otherUserId=u2'),
        NotificationNavigation.push,
      );
    });

    test('pushes group chats unless the same group is open', () {
      expect(navigate('/', '/group-chat/g1'), NotificationNavigation.push);
      expect(
        navigate('/group-chat/g2', '/group-chat/g1'),
        NotificationNavigation.push,
      );
      expect(
        navigate('/group-chat/g1', '/group-chat/g1'),
        NotificationNavigation.stay,
      );
    });

    test('replaces the stack for tab destinations', () {
      expect(
        navigate('/chat?chatId=c1&otherUserId=u2', '/?tab=friends'),
        NotificationNavigation.go,
      );
    });
  });
}
