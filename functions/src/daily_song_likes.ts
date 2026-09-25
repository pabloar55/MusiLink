import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { db } from './firebase';
import { stringList } from './firestore_values';
import { notificationText, preferredLocale, sendNotification } from './notifications';

/** Recheck delayed events against the current publication and relationship. */
export async function notifyDailySongLike(
  firestore: Firestore,
  ownerId: string,
  senderId: string,
  publishedAt: Timestamp,
  createdAt: Timestamp,
  notify = sendNotification,
  now = Timestamp.now(),
): Promise<boolean> {
  if (ownerId === senderId || now.toMillis() < publishedAt.toMillis()
    || now.toMillis() >= publishedAt.toMillis() + 86400000) return false;
  const likeRef = firestore.doc(`users/${ownerId}/daily_song_likes/${senderId}`);
  const [likeSnap, ownerSnap, senderSnap, ownerPrivateSnap, senderPrivateSnap, ownerDeletion, senderDeletion] = await Promise.all([
    likeRef.get(),
    firestore.doc(`users/${ownerId}`).get(),
    firestore.doc(`users/${senderId}`).get(),
    firestore.doc(`user_private/${ownerId}`).get(),
    firestore.doc(`user_private/${senderId}`).get(),
    firestore.doc(`account_deletions/${ownerId}`).get(),
    firestore.doc(`account_deletions/${senderId}`).get(),
  ]);
  const like = likeSnap.data();
  const owner = ownerSnap.data();
  const sender = senderSnap.data();
  const ownerPrivate = ownerPrivateSnap.data();
  const senderPrivate = senderPrivateSnap.data();
  if (!(like?.publishedAt instanceof Timestamp) || !like.publishedAt.isEqual(publishedAt)
    || !(like.createdAt instanceof Timestamp) || !like.createdAt.isEqual(createdAt)
    || (like.notificationSentFor instanceof Timestamp && like.notificationSentFor.isEqual(publishedAt))
    || !owner?.dailySong || !(owner.dailySongUpdatedAt instanceof Timestamp)
    || !owner.dailySongUpdatedAt.isEqual(publishedAt)
    || !sender || sender.username === 'deleted_user' || owner.username === 'deleted_user'
    || ownerDeletion.exists || senderDeletion.exists
    || !stringList(ownerPrivate?.friends).includes(senderId)
    || !stringList(senderPrivate?.friends).includes(ownerId)
    || stringList(ownerPrivate?.blockedUsers).includes(senderId)
    || stringList(senderPrivate?.blockedUsers).includes(ownerId)
    || typeof sender.displayName !== 'string') return false;

  await notify(ownerId, ownerPrivate, {
    title: 'MusiLink',
    body: notificationText.dailySongLiked[preferredLocale(ownerPrivate)](sender.displayName),
  }, { type: 'daily_song_liked', senderId }, `daily_song_like_${senderId}`);

  // A failure before this marker remains retryable. A repeated event uses the
  // same notification tag, replacing rather than stacking drawer entries.
  await firestore.runTransaction(async (tx) => {
    const current = (await tx.get(likeRef)).data();
    if (current?.publishedAt instanceof Timestamp && current.publishedAt.isEqual(publishedAt)
      && current.createdAt instanceof Timestamp && current.createdAt.isEqual(createdAt)) {
      tx.update(likeRef, { notificationSentFor: publishedAt });
    }
  });
  return true;
}

export const onDailySongLiked = onDocumentWritten(
  { document: 'users/{ownerId}/daily_song_likes/{senderId}', region: 'europe-southwest1', retry: true },
  async (event) => {
    const after = event.data?.after.data();
    if (!(after?.publishedAt instanceof Timestamp) || !(after.createdAt instanceof Timestamp)) return;
    if (after.notificationSentFor instanceof Timestamp && after.notificationSentFor.isEqual(after.publishedAt)) return;
    await notifyDailySongLike(db, event.params.ownerId, event.params.senderId, after.publishedAt, after.createdAt);
  },
);
