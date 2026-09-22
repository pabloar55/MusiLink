const assert = require('node:assert/strict');
const test = require('node:test');

const {
  buildModerationEmail,
  parseReportPayload,
  reportDocumentId,
  sendResendEmail,
} = require('../../lib/moderation_reports.js');

test('parseReportPayload accepts the two supported report contracts', () => {
  assert.deepEqual(parseReportPayload({
    type: 'profile',
    reason: 'harassment',
    reportedUserId: 'bob',
  }), {
    type: 'profile',
    reason: 'harassment',
    reportedUserId: 'bob',
  });
  assert.deepEqual(parseReportPayload({
    type: 'message',
    reason: 'spam',
    chatId: 'alice_bob',
    messageId: 'message-1',
  }), {
    type: 'message',
    reason: 'spam',
    chatId: 'alice_bob',
    messageId: 'message-1',
  });
});

test('parseReportPayload rejects unknown reasons, paths, and extra fields', () => {
  for (const payload of [
    { type: 'profile', reason: 'unknown', reportedUserId: 'bob' },
    { type: 'profile', reason: 'spam', reportedUserId: 'users/bob' },
    {
      type: 'message',
      reason: 'spam',
      chatId: 'alice_bob',
      messageId: 'message-1',
      reportedUserId: 'bob',
    },
  ]) {
    assert.throws(() => parseReportPayload(payload), { code: 'invalid-argument' });
  }
});

test('reportDocumentId deduplicates the same target without exposing identifiers', () => {
  const payload = {
    type: 'message',
    reason: 'spam',
    chatId: 'alice_bob',
    messageId: 'message-1',
  };
  const first = reportDocumentId('alice', payload);
  assert.equal(first, reportDocumentId('alice', { ...payload, reason: 'other' }));
  assert.notEqual(first, reportDocumentId('carol', payload));
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.equal(first.includes('alice'), false);
});

test('buildModerationEmail includes the evidence needed by the moderator', () => {
  const email = buildModerationEmail('report-1', {
    type: 'message',
    reason: 'harassment',
    reporterId: 'alice',
    reportedUserId: 'bob',
    reporter: { displayName: 'Alice', username: 'alice_name' },
    reportedUser: { displayName: 'Bob', username: 'bob_name' },
    chatId: 'alice_bob',
    messageId: 'message-1',
    message: { type: 'text', text: '<script>contenido literal</script>' },
  });

  assert.equal(email.subject, '[MusiLink] Nuevo mensaje denunciado');
  assert.equal(email.reportType, 'message');
  assert.match(email.text, /Alice @alice_name \(alice\)/);
  assert.match(email.text, /Bob @bob_name \(bob\)/);
  assert.match(email.text, /<script>contenido literal<\/script>/);
});

test('sendResendEmail uses the secret only in auth and sends idempotently', async () => {
  let request;
  const providerId = await sendResendEmail(
    're_secret',
    'MusiLink <reports@musilink.app>',
    'moderator@example.com',
    'report-1',
    {
      subject: 'Subject',
      text: 'Body',
      reportType: 'profile',
      reason: 'spam',
    },
    async (url, options) => {
      request = { url, options };
      return new Response(JSON.stringify({ id: 'resend-message-1' }), {
        status: 200,
      });
    },
  );

  assert.equal(providerId, 'resend-message-1');
  assert.equal(request.url, 'https://api.resend.com/emails');
  assert.equal(request.options.headers.Authorization, 'Bearer re_secret');
  assert.equal(
    request.options.headers['Idempotency-Key'],
    'moderation-report/report-1',
  );
  const body = JSON.parse(request.options.body);
  assert.equal(body.to[0], 'moderator@example.com');
  assert.equal(body.text, 'Body');
  assert.equal(request.options.body.includes('re_secret'), false);
});

test('sendResendEmail rejects provider errors and malformed success bodies', async () => {
  await assert.rejects(
    sendResendEmail(
      're_secret',
      'reports@musilink.app',
      'moderator@example.com',
      'report-1',
      { subject: 'Subject', text: 'Body', reportType: 'profile', reason: 'spam' },
      async () => new Response('rate limited', { status: 429 }),
    ),
    /HTTP 429/,
  );
  await assert.rejects(
    sendResendEmail(
      're_secret',
      'reports@musilink.app',
      'moderator@example.com',
      'report-1',
      { subject: 'Subject', text: 'Body', reportType: 'profile', reason: 'spam' },
      async () => new Response('{}', { status: 200 }),
    ),
    /email ID/,
  );
});
