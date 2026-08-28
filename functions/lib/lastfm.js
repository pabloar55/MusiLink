"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getSimilarArtists = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const v2_1 = require("firebase-functions/v2");
const catalog_request_1 = require("./catalog_request");
const lastFmApiKey = (0, params_1.defineSecret)('LASTFM_API_KEY');
const collabPattern = /(&|feat\.?|ft\.?)/i;
const lastFmRequestTimeoutMs = 5_000;
async function fetchLastFm(input) {
    try {
        return await fetch(input, { signal: AbortSignal.timeout(lastFmRequestTimeoutMs) });
    }
    catch (error) {
        v2_1.logger.warn('Last.fm request failed before receiving a response', {
            reason: error instanceof Error ? error.name : 'unknown',
        });
        throw new https_1.HttpsError('unavailable', 'Last.fm is temporarily unavailable');
    }
}
exports.getSimilarArtists = (0, https_1.onCall)({
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [lastFmApiKey],
}, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Login required');
    const { value: artistName, limit } = (0, catalog_request_1.parseLastFmSearchRequest)(request.data);
    const url = new URL('https://ws.audioscrobbler.com/2.0/');
    url.searchParams.set('method', 'artist.getSimilar');
    url.searchParams.set('artist', artistName);
    url.searchParams.set('api_key', lastFmApiKey.value());
    url.searchParams.set('format', 'json');
    url.searchParams.set('limit', String(limit));
    url.searchParams.set('autocorrect', '1');
    const res = await fetchLastFm(url.toString());
    if (!res.ok) {
        v2_1.logger.error('Last.fm getSimilar failed', { status: res.status, artistName });
        if (res.status === 429) {
            throw new https_1.HttpsError('resource-exhausted', 'Last.fm rate limit reached');
        }
        throw new https_1.HttpsError('internal', 'Last.fm request failed');
    }
    const data = await res.json();
    const artists = (0, catalog_request_1.isRecord)(data) && (0, catalog_request_1.isRecord)(data.similarartists)
        ? data.similarartists.artist
        : undefined;
    if (!Array.isArray(artists))
        return [];
    return artists
        .filter(catalog_request_1.isRecord)
        .map((artist) => typeof artist.name === 'string' ? artist.name : '')
        .filter((name) => name && !collabPattern.test(name))
        .slice(0, limit);
});
//# sourceMappingURL=lastfm.js.map