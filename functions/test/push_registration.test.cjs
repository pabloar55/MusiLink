const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const { deleteApp, getApps } = require('firebase-admin/app');
const { db, messaging } = require('../lib/firebase.js');
const { sendNotification } = require('../lib/notifications.js');
const { clearPushInstallations } = require('../lib/account_deletion.js');

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore emulator required');
});
after(async () => {
  await db.recursiveDelete(db.collection('push_installations'));
  await db.recursiveDelete(db.collection('user_private'));
  await Promise.all(getApps().map(deleteApp));
});

test('an offline old-account record cannot receive after FID ownership transfers', async (t) => {
  const fid = 'c123456789012345678901';
  const installationId = 'abcdefghijklmnopqrstuvwx';
  const owner = db.doc(`push_installations/${fid}`);
  const alice = db.doc(`user_private/alice/push_tokens/${installationId}`);
  const bob = db.doc(`user_private/bob/push_tokens/${installationId}`);
  await alice.set({ fid });
  await owner.set({ uid: 'alice', installationId });
  const sent = [];
  t.mock.method(messaging, 'send', async (message) => { sent.push(message); return 'sent'; });
  const notification = { title: 'Private', body: 'Message' };
  await sendNotification('alice', undefined, notification, {});
  assert.equal(sent.length, 1);

  const batch = db.batch();
  batch.set(bob, { fid });
  batch.set(owner, { uid: 'bob', installationId });
  await batch.commit();
  await sendNotification('alice', undefined, notification, {});
  assert.equal(sent.length, 1);
  await sendNotification('bob', undefined, notification, {});
  assert.equal(sent.length, 2);

  // Deleting Alice must not erase Bob's new claim of the same FID.
  await db.doc('push_installations/d123456789012345678901').set({ uid: 'alice', installationId });
  assert.equal(await clearPushInstallations('alice'), 1);
  assert.equal((await owner.get()).data().uid, 'bob');
  await clearPushInstallations('bob');
  // Even if old private cleanup was lost, deleting the owner cannot revive it.
  await sendNotification('alice', undefined, notification, {});
  assert.equal(sent.length, 2);
});
