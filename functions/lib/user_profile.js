"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createUserProfile = void 0;
const v2_1 = require("firebase-functions/v2");
const https_1 = require("firebase-functions/v2/https");
const firebase_1 = require("./firebase");
const username_claim_1 = require("./username_claim");
exports.createUserProfile = (0, https_1.onCall)({ region: 'europe-southwest1', enforceAppCheck: true }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    }
    const email = typeof request.auth?.token.email === 'string'
        ? request.auth.token.email
        : '';
    try {
        return await (0, username_claim_1.claimUsernameAndCreateProfile)(firebase_1.db, uid, email, request.data);
    }
    catch (error) {
        if (error instanceof https_1.HttpsError)
            throw error;
        v2_1.logger.error('createUserProfile: unhandled error', { uid, error });
        throw new https_1.HttpsError('internal', 'Could not create the user profile.');
    }
});
//# sourceMappingURL=user_profile.js.map