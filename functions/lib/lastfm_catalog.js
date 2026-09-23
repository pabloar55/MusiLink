"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lastFmCatalog = exports.LastFmCatalog = void 0;
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const v2_1 = require("firebase-functions/v2");
const catalog_request_1 = require("./catalog_request");
const firebase_1 = require("./firebase");
const requestTimeoutMs = 5_000;
const cacheTtlMs = 24 * 60 * 60 * 1000;
const emptyCacheTtlMs = 5 * 60 * 1000;
function responseCacheTtl(res, empty) {
    const control = res.headers.get('cache-control') ?? '';
    if (/(?:^|,)\s*(?:no-store|no-cache|private)(?:\s|=|,|$)/i.test(control))
        return 0;
    let ttl = empty ? emptyCacheTtlMs : cacheTtlMs;
    const maxAge = /(?:^|,)\s*s-maxage\s*=\s*"?(\d+)/i.exec(control)
        ?? /(?:^|,)\s*max-age\s*=\s*"?(\d+)/i.exec(control);
    const now = Date.now();
    const responseDate = Date.parse(res.headers.get('date') ?? '');
    const apparentAge = Number.isFinite(responseDate) ? Math.max(0, now - responseDate) : 0;
    const age = Math.max(apparentAge, (Number(res.headers.get('age')) || 0) * 1000);
    if (maxAge) {
        ttl = Math.min(ttl, Number(maxAge[1]) * 1000 - age);
    }
    else if (res.headers.has('expires')) {
        const expires = Date.parse(res.headers.get('expires'));
        // Treat an invalid Expires value as already expired.
        const origin = Number.isFinite(responseDate) ? responseDate : now;
        ttl = Number.isFinite(expires) ? Math.min(ttl, expires - origin - age) : 0;
    }
    return Math.max(0, ttl);
}
/** Shared Firestore cache; pending requests are also coalesced per instance. */
class LastFmCatalog {
    firestore;
    pending = new Map();
    constructor(firestore) {
        this.firestore = firestore;
    }
    async getStrings(method, artistName, apiKey, parse) {
        const artist = artistName.trim().normalize('NFC').replace(/\s+/g, ' ');
        // Version the parsed representation; never put credentials in the key/data.
        const key = (0, node_crypto_1.createHash)('sha256')
            .update(JSON.stringify(['v1', method, artist.toLowerCase()]))
            .digest('hex');
        const existing = this.pending.get(key);
        if (existing)
            return existing;
        const request = this.load(key, method, artist, apiKey, parse);
        this.pending.set(key, request);
        try {
            return await request;
        }
        finally {
            this.pending.delete(key);
        }
    }
    async load(key, method, artistName, apiKey, parse) {
        const ref = this.firestore.doc(`lastfm_cache/${key}`);
        const cached = (await ref.get()).data();
        if (cached?.expiresAt instanceof firestore_1.Timestamp
            && cached.expiresAt.toMillis() > Date.now()
            && Array.isArray(cached.values)
            && cached.values.every((value) => typeof value === 'string')) {
            return cached.values;
        }
        const url = new URL('https://ws.audioscrobbler.com/2.0/');
        url.searchParams.set('method', method);
        url.searchParams.set('artist', artistName);
        url.searchParams.set('api_key', apiKey);
        url.searchParams.set('format', 'json');
        url.searchParams.set('autocorrect', '1');
        if (method === 'artist.getSimilar') {
            // Cache the full supported list even when the caller only needs one name.
            url.searchParams.set('limit', String(catalog_request_1.catalogSearchMaxLimit));
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
        // Parsers reject malformed bodies. Only successful results (including a
        // genuinely empty list) may enter either backend or client caches.
        const values = parse(data);
        const ttl = responseCacheTtl(response, values.length === 0);
        if (ttl > 0) {
            try {
                await ref.set({ values, expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + ttl) });
            }
            catch {
                v2_1.logger.warn('Unable to cache Last.fm response', { method });
            }
        }
        return values;
    }
}
exports.LastFmCatalog = LastFmCatalog;
exports.lastFmCatalog = new LastFmCatalog(firebase_1.db);
//# sourceMappingURL=lastfm_catalog.js.map