"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.acceptTerms = exports.currentTermsVersion = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const firebase_1 = require("./firebase");
exports.currentTermsVersion = '2026-09-18';
exports.acceptTerms = (0, https_1.onCall)({ region: 'europe-southwest1', enforceAppCheck: true }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError('unauthenticated', 'Authentication is required.');
    }
    if (request.data?.version !== exports.currentTermsVersion) {
        throw new https_1.HttpsError('invalid-argument', 'Unsupported terms version.');
    }
    const acceptanceRef = firebase_1.db.doc(`user_private/${uid}/terms_acceptances/current`);
    const deletionRef = firebase_1.db.doc(`account_deletions/${uid}`);
    await firebase_1.db.runTransaction(async (transaction) => {
        const [deletion, acceptance] = await Promise.all([
            transaction.get(deletionRef),
            transaction.get(acceptanceRef),
        ]);
        if (deletion.exists) {
            throw new https_1.HttpsError('failed-precondition', 'Account deletion is pending.');
        }
        if (acceptance.data()?.version === exports.currentTermsVersion)
            return;
        transaction.set(acceptanceRef, {
            version: exports.currentTermsVersion,
            acceptedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return { version: exports.currentTermsVersion };
});
//# sourceMappingURL=terms_acceptance.js.map