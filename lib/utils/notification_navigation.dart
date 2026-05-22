import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

String? notificationLocationFromData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  switch (type) {
    case 'new_message':
      final chatId = data['chatId']?.toString();
      final otherUserId = data['otherUserId']?.toString();
      final otherUserName = data['otherUserName']?.toString();
      if (chatId == null || otherUserId == null) return '/?tab=messages';

      return Uri(
        path: '/chat',
        queryParameters: {
          'chatId': chatId,
          'otherUserId': otherUserId,
          if (otherUserName != null && otherUserName.trim().isNotEmpty)
            'otherUserName': otherUserName,
        },
      ).toString();
    case 'friend_request':
    case 'friend_request_accepted':
      return '/?tab=friends';
  }
  return null;
}

void handleNotificationNavigation(
  Map<String, dynamic> data,
  BuildContext context,
) {
  final location = notificationLocationFromData(data);
  if (location == null) return;
  if (location.startsWith('/chat')) {
    context.push(location);
  } else {
    context.go(location);
  }
}
