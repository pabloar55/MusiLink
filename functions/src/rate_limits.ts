import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { timestampValue } from './firestore_values';

interface FixedWindowResult {
  limited: boolean;
  windowStart: Timestamp;
  count: number;
}

export function advanceFixedWindow(
  windowStartValue: unknown,
  countValue: unknown,
  now: Timestamp,
  windowMs: number,
  maximum: number,
): FixedWindowResult {
  const windowStart = timestampValue(windowStartValue);
  const count = typeof countValue === 'number'
    && Number.isInteger(countValue)
    && countValue >= 0
    ? countValue
    : 0;
  if (!windowStart || now.toMillis() - windowStart.toMillis() > windowMs) {
    return { limited: false, windowStart: now, count: 1 };
  }
  if (count >= maximum) {
    return { limited: true, windowStart, count };
  }
  return { limited: false, windowStart, count: count + 1 };
}

// Spotify artist/track searches share a budget. Similar-artist suggestions have
// their own budget so selecting an artist does not consume it twice.
export const catalogSearchWindowMs = 60_000;
export const maxCatalogSearchesPerWindow = 60;
export type CatalogSearchQuota = 'spotifySearch' | 'lastFmSimilar';

export async function consumeCatalogSearchQuota(
  firestore: Firestore,
  uid: string,
  quota: CatalogSearchQuota,
  now = Timestamp.now(),
): Promise<void> {
  const limiterRef = firestore.doc(`rate_limits/${uid}`);
  const windowField = `${quota}WindowStart`;
  const countField = `${quota}Count`;
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(limiterRef);
    const data = snapshot.data();
    const next = advanceFixedWindow(
      data?.[windowField],
      data?.[countField],
      now,
      catalogSearchWindowMs,
      maxCatalogSearchesPerWindow,
    );
    if (next.limited) {
      throw new HttpsError('resource-exhausted', 'Catalog search rate limit reached.');
    }
    // Reserve before calling external providers. Failed upstream requests still cost quota.
    transaction.set(limiterRef, {
      [windowField]: next.windowStart,
      [countField]: next.count,
    }, { merge: true });
  });
}
