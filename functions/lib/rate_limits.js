"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.maxCatalogSearchesPerWindow = exports.catalogSearchWindowMs = void 0;
exports.advanceFixedWindow = advanceFixedWindow;
exports.consumeCatalogSearchQuota = consumeCatalogSearchQuota;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const firestore_values_1 = require("./firestore_values");
function advanceFixedWindow(windowStartValue, countValue, now, windowMs, maximum) {
    const windowStart = (0, firestore_values_1.timestampValue)(windowStartValue);
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
exports.catalogSearchWindowMs = 60_000;
exports.maxCatalogSearchesPerWindow = 60;
async function consumeCatalogSearchQuota(firestore, uid, quota, now = firestore_1.Timestamp.now()) {
    const limiterRef = firestore.doc(`rate_limits/${uid}`);
    const windowField = `${quota}WindowStart`;
    const countField = `${quota}Count`;
    await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(limiterRef);
        const data = snapshot.data();
        const next = advanceFixedWindow(data?.[windowField], data?.[countField], now, exports.catalogSearchWindowMs, exports.maxCatalogSearchesPerWindow);
        if (next.limited) {
            throw new https_1.HttpsError('resource-exhausted', 'Catalog search rate limit reached.');
        }
        // Reserve before calling external providers. Failed upstream requests still cost quota.
        transaction.set(limiterRef, {
            [windowField]: next.windowStart,
            [countField]: next.count,
        }, { merge: true });
    });
}
//# sourceMappingURL=rate_limits.js.map