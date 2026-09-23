"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getSimilarArtists = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const firebase_1 = require("./firebase");
const rate_limits_1 = require("./rate_limits");
const catalog_request_1 = require("./catalog_request");
const lastfm_catalog_1 = require("./lastfm_catalog");
const lastFmApiKey = (0, params_1.defineSecret)('LASTFM_API_KEY');
const collabPattern = /(&|feat\.?|ft\.?)/i;
exports.getSimilarArtists = (0, https_1.onCall)({
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [lastFmApiKey],
}, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Login required');
    const { value: artistName, limit } = (0, catalog_request_1.parseLastFmSearchRequest)(request.data);
    await (0, rate_limits_1.consumeCatalogSearchQuota)(firebase_1.db, request.auth.uid, 'lastFmSimilar');
    const artists = await lastfm_catalog_1.lastFmCatalog.getStrings('artist.getSimilar', artistName, lastFmApiKey.value(), (data) => {
        const items = (0, catalog_request_1.isRecord)(data) && (0, catalog_request_1.isRecord)(data.similarartists)
            ? data.similarartists.artist
            : undefined;
        if (!Array.isArray(items) || items.some((artist) => (!(0, catalog_request_1.isRecord)(artist) || typeof artist.name !== 'string' || !artist.name.trim()))) {
            throw new https_1.HttpsError('unavailable', 'Last.fm returned an invalid artist list');
        }
        return items
            .filter(catalog_request_1.isRecord)
            .map((artist) => typeof artist.name === 'string' ? artist.name : '')
            .filter((name) => name && !collabPattern.test(name))
            .slice(0, catalog_request_1.catalogSearchMaxLimit);
    });
    return artists.slice(0, limit);
});
//# sourceMappingURL=lastfm.js.map