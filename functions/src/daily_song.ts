import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  Timestamp,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { db } from './firebase';
import { FriendSong, loadFriendSongs, unblockedFriendIds } from './friend_digest';
import {
  engagementPushField,
  notificationText,
  preferredLocale,
  sendNotification,
  SupportedLocale,
} from './notifications';

const userPrivateCollection = 'user_private';
const dailySongLifetimeMs = 24 * 60 * 60 * 1000;
const dailySongExpiryBatchSize = 200;

export function hasExpiredDailySong(
  data: DocumentData | undefined,
  expiresBefore: Timestamp,
): boolean {
  const updatedAt = data?.dailySongUpdatedAt;
  return updatedAt instanceof Timestamp &&
    updatedAt.toMillis() <= expiresBefore.toMillis() &&
    Boolean(data?.dailySong);
}

// Removing the song and claiming the day's reminder are one write: the friend
// digest sees either the song still published or the reminder already taken,
// so it can never be sent alongside the expiry notice.
export async function expireDailySong(
  userRef: DocumentReference,
  expiresBefore: Timestamp,
): Promise<boolean> {
  const privateRef = db.doc(`${userPrivateCollection}/${userRef.id}`);
  return db.runTransaction(async (transaction) => {
    const [current, privateProfile] = await Promise.all([
      transaction.get(userRef),
      transaction.get(privateRef),
    ]);
    const data = current.data();
    const updatedAt = data?.dailySongUpdatedAt;
    if (
      !(updatedAt instanceof Timestamp) ||
      updatedAt.toMillis() > expiresBefore.toMillis()
    ) {
      return false;
    }

    // Avoid an orphaned legacy timestamp blocking the oldest-results query.
    if (!hasExpiredDailySong(data, expiresBefore)) {
      transaction.update(userRef, { dailySongUpdatedAt: FieldValue.delete() });
      return false;
    }

    transaction.update(userRef, {
      dailySong: FieldValue.delete(),
      dailySongUpdatedAt: FieldValue.delete(),
    });
    if (privateProfile.exists) {
      transaction.update(privateRef, {
        [engagementPushField]: FieldValue.serverTimestamp(),
      });
    }
    return true;
  });
}

export function dailySongExpiredBody(locale: SupportedLocale, friendCount: number): string {
  if (friendCount <= 0) return notificationText.dailySongExpired[locale]();
  if (friendCount === 1) return notificationText.dailySongExpiredFriend[locale]();
  return notificationText.dailySongExpiredFriends[locale](String(friendCount));
}

/** Tells the owner their song expired, mentioning friends who have published. */
export async function notifyDailySongExpired(
  firestore: Firestore,
  uid: string,
  activeAfter: number,
  cache: Map<string, FriendSong | null>,
  notify = sendNotification,
): Promise<void> {
  const privateProfile = await firestore.doc(`${userPrivateCollection}/${uid}`).get();
  const privateData = privateProfile.data();
  let friendCount = 0;
  try {
    const songs = await loadFriendSongs(
      firestore,
      unblockedFriendIds(privateData),
      activeAfter,
      cache,
    );
    friendCount = songs.length;
  } catch (error) {
    // The song is already gone, so the reminder must not depend on this count.
    logger.warn('notifyDailySongExpired: friend songs unavailable', { uid, error });
  }

  await notify(
    uid,
    privateData,
    {
      title: 'MusiLink',
      body: dailySongExpiredBody(preferredLocale(privateData), friendCount),
    },
    { type: 'daily_song_expired' },
    'daily_song_expired',
  );
}

// Firestore keeps the publication time on the public profile. The transaction
// protects a replacement song published while this query is running.
export const expireDailySongs = onSchedule(
  {
    schedule: 'every 1 minutes',
    // Cloud Scheduler is not available in europe-southwest1 (Madrid).
    region: 'europe-west1',
    timeZone: 'UTC',
    timeoutSeconds: 300,
    retryCount: 3,
  },
  async () => {
    const expiresBefore = Timestamp.fromMillis(Date.now() - dailySongLifetimeMs);
    const expiredProfiles = await db
      .collection('users')
      .where('dailySongUpdatedAt', '<=', expiresBefore)
      .orderBy('dailySongUpdatedAt')
      .limit(dailySongExpiryBatchSize)
      .get();

    let expiredCount = 0;
    const friendSongs = new Map<string, FriendSong | null>();
    const concurrency = 20;
    for (let index = 0; index < expiredProfiles.docs.length; index += concurrency) {
      const chunk = expiredProfiles.docs.slice(index, index + concurrency);
      await Promise.all(chunk.map(async (profile) => {
        const expired = await expireDailySong(profile.ref, expiresBefore);
        if (!expired) return;

        expiredCount += 1;
        await notifyDailySongExpired(
          db,
          profile.id,
          expiresBefore.toMillis(),
          friendSongs,
        );
      }));
    }

    logger.info('expireDailySongs: expiry cycle completed', {
      candidates: expiredProfiles.size,
      expired: expiredCount,
      expiresBefore: expiresBefore.toDate().toISOString(),
    });
  },
);
