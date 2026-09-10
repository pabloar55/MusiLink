const assert = require('node:assert/strict');
const { test } = require('node:test');
const { confirmPushDelivery, acknowledgeChatDelivery } = require('../../lib/chat_delivery.js');

test('rejects malformed delivery capabilities before accessing Firestore', async () => {
  for (const body of [null, '', {}, { chatId: '../other', messageId: 'm', deliveryToken: 'a'.repeat(64) },
    { chatId: 'chat', messageId: 'nested/path', deliveryToken: 'a'.repeat(64) },
    { chatId: 'chat', messageId: 'm', deliveryToken: 'invalid' }]) {
    assert.equal(await confirmPushDelivery(body), false);
  }
});

test('delivery endpoint rejects non-POST requests', async () => {
  let status;
  await acknowledgeChatDelivery({ method: 'GET' }, {
    status(value) { status = value; return this; }, end() {},
  });
  assert.equal(status, 405);
});
