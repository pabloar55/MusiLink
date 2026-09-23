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

// One shared budget prevents switching catalog endpoints to bypass the limit.
// Artist searches can also issue up to ten Last.fm genre lookups; those are
// bounded by the existing result limit and covered by the admitted search.
export const catalogSearchWindowMs = 60_000;
export const maxCatalogSearchesPerWindow = 60;

export async function consumeCatalogSearchQuota(
  firestore: Firestore,
  uid: string,
  now = Timestamp.now(),
): Promise<void> {
  const limiterRef = firestore.doc(`rate_limits/${uid}`);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(limiterRef);
    const data = snapshot.data();
    const next = advanceFixedWindow(
      data?.catalogSearchWindowStart,
      data?.catalogSearchCount,
      now,
      catalogSearchWindowMs,
      maxCatalogSearchesPerWindow,
    );
    if (next.limited) {
      throw new HttpsError('resource-exhausted', 'Catalog search rate limit reached.');
    }
    // Reserve before any external I/O. Failed upstream requests still cost quota.
    transaction.set(limiterRef, {
      catalogSearchWindowStart: next.windowStart,
      catalogSearchCount: next.count,
    }, { merge: true });
  });
}
