/* global firebase */

// Register this before Firebase Messaging so notification clicks use MusiLink's
// route instead of Firebase's generic root-page handler.
self.addEventListener('notificationclick', (event) => {
  event.stopImmediatePropagation();
  event.notification.close();

  const notificationData = event.notification.data || {};
  const fcmData = notificationData.FCM_MSG?.data || {};
  const path = notificationData.path || fcmData.notificationPath || '/';
  const targetUrl = new URL(path, self.location.origin).href;

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then(async (windowClients) => {
        const sameOriginClient = windowClients.find((client) => {
          try {
            return new URL(client.url).origin === self.location.origin;
          } catch (_) {
            return false;
          }
        });

        if (sameOriginClient) {
          if ('navigate' in sameOriginClient) {
            try {
              await sameOriginClient.navigate(targetUrl);
            } catch (_) {
              // Focusing the existing window is still better than opening a
              // duplicate when a browser does not implement navigate().
            }
          }
          return sameOriginClient.focus();
        }
        return self.clients.openWindow(targetUrl);
      }),
  );
});

// FlutterFire 16.4.x is tested against Firebase JS 12.15.0. A classic
// service worker is required by the plugin registration API, so the compat
// build is used here while the app itself continues using the modular SDK.
importScripts(
  'https://www.gstatic.com/firebasejs/12.15.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/12.15.0/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyCFKR5xGOFwOgRPaA1haaeZwLP8bncFkm0',
  appId: '1:701824546350:web:3c3a7d84fc778ce71691bf',
  messagingSenderId: '701824546350',
  projectId: 'musi-link-e7759',
  authDomain: 'musi-link-e7759.firebaseapp.com',
  storageBucket: 'musi-link-e7759.firebasestorage.app',
});

// Initializing Messaging installs the background push handler. Every server
// payload includes a webpush.notification block, so no duplicate manual
// showNotification call is needed.
firebase.messaging();
