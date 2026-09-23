"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchLastFm = fetchLastFm;
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const catalog_request_1 = require("./catalog_request");
const requestTimeoutMs = 5_000;
async function fetchLastFm(method, artistName, apiKey, limit = 10) {
    const url = new URL('https://ws.audioscrobbler.com/2.0/');
    url.searchParams.set('method', method);
    url.searchParams.set('artist', artistName);
    url.searchParams.set('api_key', apiKey);
    url.searchParams.set('format', 'json');
    url.searchParams.set('autocorrect', '1');
    if (method === 'artist.getSimilar') {
        url.searchParams.set('limit', String(limit));
    }
    let response;
    try {
        response = await fetch(url.toString(), {
            headers: { 'User-Agent': 'MusiLink/1.0' },
            signal: AbortSignal.timeout(requestTimeoutMs),
        });
    }
    catch (error) {
        v2_1.logger.warn('Last.fm request failed before receiving a response', {
            reason: error instanceof Error ? error.name : 'unknown',
        });
        throw new https_1.HttpsError('unavailable', 'Last.fm is temporarily unavailable');
    }
    if (!response.ok) {
        throw new https_1.HttpsError(response.status === 429 ? 'resource-exhausted' : 'unavailable', 'Last.fm request failed');
    }
    let data;
    try {
        data = await response.json();
    }
    catch {
        throw new https_1.HttpsError('unavailable', 'Last.fm returned an invalid response');
    }
    // Last.fm also reports API errors inside otherwise successful HTTP responses.
    if ((0, catalog_request_1.isRecord)(data) && data.error !== undefined) {
        throw new https_1.HttpsError(Number(data.error) === 29 ? 'resource-exhausted' : 'unavailable', 'Last.fm request failed');
    }
    return data;
}
//# sourceMappingURL=lastfm_request.js.map