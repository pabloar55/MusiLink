"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeUsername = normalizeUsername;
exports.claimUsernameAndCreateProfile = claimUsernameAndCreateProfile;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const usernamePattern = /^[a-z0-9_]{3,20}$/;
const reservedUsernames = new Set(['deleted_user']);
function utf8Length(value) {
    return new TextEncoder().encode(value).length;
}
function normalizeUsername(value) {
    return value.trim().toLowerCase();
}
function validatedClaim(data) {
    const input = data;
    const displayName = typeof input?.displayName === 'string'
        ? input.displayName.trim()
        : '';
    const username = typeof input?.username === 'string'
        ? normalizeUsername(input.username)
        : '';
    if (displayName.length === 0 || utf8Length(displayName) > 100) {
        throw new https_1.HttpsError('invalid-argument', 'Display name must contain between 1 and 100 UTF-8 bytes.');
    }
    if (!usernamePattern.test(username) || reservedUsernames.has(username)) {
        throw new https_1.HttpsError('invalid-argument', 'Username is invalid or reserved.');
    }
    return { displayName, username };
}
/**
 * Atomically reserves a username and saves a private setup draft.
 * Exported separately from the callable wrapper so the contention behavior can
 * be exercised against the Firestore emulator.
 */
async function claimUsernameAndCreateProfile(db, uid, email, data) {
    const { displayName, username } = validatedClaim(data);
    const reservationRef = db.doc(`usernames/${username}`);
    const publicProfileRef = db.doc(`users/${uid}`);
    const privateProfileRef = db.doc(`user_private/${uid}`);
    const deletionRef = db.doc(`account_deletions/${uid}`);
    await db.runTransaction(async (transaction) => {
        const [reservation, publicProfile, privateProfile, deletion] = await transaction.getAll(reservationRef, publicProfileRef, privateProfileRef, deletionRef);
        if (deletion.exists) {
            throw new https_1.HttpsError('failed-precondition', 'Account deletion is pending.');
        }
        const reservationOwner = reservation.data()?.uid;
        if (reservation.exists && reservationOwner !== uid) {
            throw new https_1.HttpsError('already-exists', 'Username is already taken.');
        }
        if (publicProfile.exists) {
            const storedUsername = publicProfile.data()?.username;
            if (storedUsername !== username) {
                throw new https_1.HttpsError('failed-precondition', 'The authenticated user already has a profile.');
            }
        }
        const draft = privateProfile.data()?.setupProfile;
        if (privateProfile.exists && !publicProfile.exists && draft?.username !== username) {
            throw new https_1.HttpsError('failed-precondition', 'A private profile already exists without a public profile.');
        }
        if (!reservation.exists) {
            transaction.create(reservationRef, {
                uid,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        if (!privateProfile.exists) {
            transaction.create(privateProfileRef, {
                ...(!publicProfile.exists ? {
                    setupProfile: { displayName, username, photoUrl: '', musicProfileVersion: 0 },
                } : {}),
                email,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                lastLogin: firestore_1.FieldValue.serverTimestamp(),
                friends: [],
            });
        }
    });
    return { username };
}
//# sourceMappingURL=username_claim.js.map