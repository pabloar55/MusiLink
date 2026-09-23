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
// One shared budget prevents switching catalog endpoints to bypass the limit.
// Artist searches can also issue up to ten Last.fm genre lookups; those are
// bounded by the existing result limit and covered by the admitted search.
exports.catalogSearchWindowMs = 60_000;
exports.maxCatalogSearchesPerWindow = 60;
async function consumeCatalogSearchQuota(firestore, uid, now = firestore_1.Timestamp.now()) {
    const limiterRef = firestore.doc(`rate_limits/${uid}`);
    await firestore.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(limiterRef);
        const data = snapshot.data();
        const next = advanceFixedWindow(data?.catalogSearchWindowStart, data?.catalogSearchCount, now, exports.catalogSearchWindowMs, exports.maxCatalogSearchesPerWindow);
        if (next.limited) {
            throw new https_1.HttpsError('resource-exhausted', 'Catalog search rate limit reached.');
        }
        // Reserve before any external I/O. Failed upstream requests still cost quota.
        transaction.set(limiterRef, {
            catalogSearchWindowStart: next.windowStart,
            catalogSearchCount: next.count,
        }, { merge: true });
    });
}
//# sourceMappingURL=rate_limits.js.map