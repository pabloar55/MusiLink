import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Timestamp,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { db } from './firebase';
import {
  notificationText,
  preferredLocale,
  sendNotification,
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

async function expireDailySong(
  userRef: DocumentReference,
  expiresBefore: Timestamp,
): Promise<boolean> {
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(userRef);
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
    return true;
  });
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
    const concurrency = 20;
    for (let index = 0; index < expiredProfiles.docs.length; index += concurrency) {
      const chunk = expiredProfiles.docs.slice(index, index + concurrency);
      await Promise.all(chunk.map(async (profile) => {
        const expired = await expireDailySong(profile.ref, expiresBefore);
        if (!expired) return;

        expiredCount += 1;
        const privateProfile = await db
          .doc(`${userPrivateCollection}/${profile.id}`)
          .get();
        const privateData = privateProfile.data();
        const locale = preferredLocale(privateData);
        await sendNotification(
          profile.id,
          privateData,
          {
            title: 'MusiLink',
            body: notificationText.dailySongExpired[locale](),
          },
          { type: 'daily_song_expired' },
          'daily_song_expired',
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
