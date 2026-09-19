import { FieldValue } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db } from './firebase';

export const currentTermsVersion = '2026-09-18';

export const acceptTerms = onCall(
  { region: 'europe-southwest1', enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Authentication is required.');
    }
    if (request.data?.version !== currentTermsVersion) {
      throw new HttpsError('invalid-argument', 'Unsupported terms version.');
    }

    const acceptanceRef = db.doc(`user_private/${uid}/terms_acceptances/current`);
    const deletionRef = db.doc(`account_deletions/${uid}`);
    await db.runTransaction(async (transaction) => {
      const [deletion, acceptance] = await Promise.all([
        transaction.get(deletionRef),
        transaction.get(acceptanceRef),
      ]);
      if (deletion.exists) {
        throw new HttpsError('failed-precondition', 'Account deletion is pending.');
      }
      if (acceptance.data()?.version === currentTermsVersion) return;
      transaction.set(acceptanceRef, {
        version: currentTermsVersion,
        acceptedAt: FieldValue.serverTimestamp(),
      });
    });

    return { version: currentTermsVersion };
  },
);
