const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');
const source = readFileSync(`${__dirname}/../web/firebase-messaging-sw.js`, 'utf8');

function worker(fetch) {
  let receive;
  runInNewContext(source, {
    self: { addEventListener() {} }, importScripts() {},
    firebase: { initializeApp() {}, messaging: () => ({
      onBackgroundMessage(callback) { receive = callback; },
    }) }, fetch,
  });
  return (data) => receive({ data });
}

test('background push acknowledges exactly the received message without opening a window', async () => {
  const requests = [];
  const receive = worker(async (url, options) => requests.push([url, options]));
  await receive({ type: 'new_message', chatId: 'chat', messageId: 'message', deliveryToken: 'token' });
  assert.equal(requests.length, 1);
  assert.equal(requests[0][0], '/api/chat-delivery');
  assert.equal(requests[0][1].method, 'POST');
  assert.deepEqual(JSON.parse(requests[0][1].body), {
    chatId: 'chat', messageId: 'message', deliveryToken: 'token',
  });
});

test('ignores unrelated and legacy pushes, tolerates a network failure', async () => {
  let requests = 0;
  const receive = worker(async () => { requests++; throw new Error('offline'); });
  await receive({ type: 'friend_request' });
  await receive({ type: 'new_message', chatId: 'chat' });
  assert.equal(requests, 0);
  await receive({ type: 'new_message', chatId: 'chat', messageId: 'message', deliveryToken: 'token' });
  assert.equal(requests, 1);
});
