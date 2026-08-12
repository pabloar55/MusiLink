import { logger } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { db } from './firebase';
import { claimUsernameAndCreateProfile as claimUsername } from './username_claim';

export const createUserProfile = onCall(
  { region: 'europe-southwest1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Authentication is required.');
    }

    const email = typeof request.auth?.token.email === 'string'
      ? request.auth.token.email
      : '';

    try {
      return await claimUsername(db, uid, email, request.data);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error('createUserProfile: unhandled error', { uid, error });
      throw new HttpsError('internal', 'Could not create the user profile.');
    }
  },
);
