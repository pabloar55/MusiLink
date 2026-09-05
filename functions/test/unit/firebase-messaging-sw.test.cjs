const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerSource = fs.readFileSync(
  path.join(__dirname, '../../../web/firebase-messaging-sw.js'),
  'utf8',
);

function loadNotificationClickHandler({ clients }) {
  let notificationClick;
  const self = {
    location: { origin: 'https://musilink.example' },
    clients,
    addEventListener(type, listener) {
      if (type === 'notificationclick') notificationClick = listener;
    },
  };
  vm.runInNewContext(workerSource, {
    URL,
    self,
    importScripts() {},
    firebase: {
      initializeApp() {},
      messaging() {},
    },
  });
  return notificationClick;
}

test('notification clicks open Flutter hash routes', async () => {
  let openedUrl;
  const handler = loadNotificationClickHandler({
    clients: {
      async matchAll() {
        return [];
      },
      async openWindow(url) {
        openedUrl = url;
      },
    },
  });
  let clickWork;

  handler({
    stopImmediatePropagation() {},
    notification: {
      data: { path: '/chat?chatId=chat-1&otherUserId=user-2' },
      close() {},
    },
    waitUntil(work) {
      clickWork = work;
    },
  });
  await clickWork;

  assert.equal(
    openedUrl,
    'https://musilink.example/#/chat?chatId=chat-1&otherUserId=user-2',
  );
});

test('notification clicks navigate an open PWA using nested FCM data', async () => {
  let navigatedUrl;
  let focused = false;
  const client = {
    url: 'https://musilink.example/#/',
    async navigate(url) {
      navigatedUrl = url;
    },
    async focus() {
      focused = true;
    },
  };
  const handler = loadNotificationClickHandler({
    clients: {
      async matchAll() {
        return [client];
      },
      async openWindow() {
        assert.fail('must reuse the existing PWA window');
      },
    },
  });
  let clickWork;

  handler({
    stopImmediatePropagation() {},
    notification: {
      data: { FCM_MSG: { data: { notificationPath: '/?tab=friends' } } },
      close() {},
    },
    waitUntil(work) {
      clickWork = work;
    },
  });
  await clickWork;

  assert.equal(navigatedUrl, 'https://musilink.example/#/?tab=friends');
  assert.equal(focused, true);
});
