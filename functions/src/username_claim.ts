import { HttpsError } from 'firebase-functions/v2/https';
import {
  FieldValue,
  Firestore,
} from 'firebase-admin/firestore';

const usernamePattern = /^[a-z0-9_]{3,20}$/;
const reservedUsernames = new Set(['deleted_user']);

interface UsernameClaimData {
  displayName?: unknown;
  username?: unknown;
}

export interface UsernameClaimResult {
  username: string;
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length;
}

export function normalizeUsername(value: string): string {
  return value.trim().toLowerCase();
}

function validatedClaim(data: unknown): {
  displayName: string;
  username: string;
} {
  const input = data as UsernameClaimData | null;
  const displayName = typeof input?.displayName === 'string'
    ? input.displayName.trim()
    : '';
  const username = typeof input?.username === 'string'
    ? normalizeUsername(input.username)
    : '';

  if (displayName.length === 0 || utf8Length(displayName) > 100) {
    throw new HttpsError(
      'invalid-argument',
      'Display name must contain between 1 and 100 UTF-8 bytes.',
    );
  }
  if (!usernamePattern.test(username) || reservedUsernames.has(username)) {
    throw new HttpsError('invalid-argument', 'Username is invalid or reserved.');
  }

  return { displayName, username };
}

/**
 * Atomically reserves a normalized username and creates both profile documents.
 * Exported separately from the callable wrapper so the contention behavior can
 * be exercised against the Firestore emulator.
 */
export async function claimUsernameAndCreateProfile(
  db: Firestore,
  uid: string,
  email: string,
  data: unknown,
): Promise<UsernameClaimResult> {
  const { displayName, username } = validatedClaim(data);
  const reservationRef = db.doc(`usernames/${username}`);
  const publicProfileRef = db.doc(`users/${uid}`);
  const privateProfileRef = db.doc(`user_private/${uid}`);

  await db.runTransaction(async (transaction) => {
    const [reservation, publicProfile, privateProfile] = await transaction.getAll(
      reservationRef,
      publicProfileRef,
      privateProfileRef,
    );

    const reservationOwner = reservation.data()?.uid;
    if (reservation.exists && reservationOwner !== uid) {
      throw new HttpsError('already-exists', 'Username is already taken.');
    }

    if (publicProfile.exists) {
      const storedUsername = publicProfile.data()?.username;
      if (storedUsername !== username) {
        throw new HttpsError(
          'failed-precondition',
          'The authenticated user already has a profile.',
        );
      }
    }

    if (privateProfile.exists && !publicProfile.exists) {
      throw new HttpsError(
        'failed-precondition',
        'A private profile already exists without a public profile.',
      );
    }

    if (!reservation.exists) {
      transaction.create(reservationRef, {
        uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    if (!publicProfile.exists) {
      transaction.create(publicProfileRef, {
        displayName,
        username,
        photoUrl: '',
        musicProfileVersion: 0,
      });
    }
    if (!privateProfile.exists) {
      transaction.create(privateProfileRef, {
        email,
        createdAt: FieldValue.serverTimestamp(),
        lastLogin: FieldValue.serverTimestamp(),
        friends: [],
      });
    }
  });

  return { username };
}
