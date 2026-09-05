import 'dart:js_interop';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:web/web.dart' as web;

Future<void> showWebForegroundNotification(
  RemoteMessage message, {
  required bool silent,
}) async {
  final notification = message.notification;
  if (notification == null) return;

  final path = message.data['notificationPath'];
  final registration = await web.window.navigator.serviceWorker.ready.toDart;
  await registration
      .showNotification(
        notification.title ?? 'MusiLink',
        web.NotificationOptions(
          body: notification.body ?? '',
          icon: '/icons/Icon-192.png',
          badge: '/icons/Icon-192.png',
          silent: silent,
          data: <String, Object?>{
            'path': path is String && path.startsWith('/') ? path : '/',
          }.jsify(),
        ),
      )
      .toDart;
}
