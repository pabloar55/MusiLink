import { createHash } from 'node:crypto';
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { catalogSearchMaxLimit, isRecord } from './catalog_request';
import { db } from './firebase';

type LastFmMethod = 'artist.getSimilar' | 'artist.getTopTags';
const requestTimeoutMs = 5_000;
const cacheTtlMs = 24 * 60 * 60 * 1000;
const emptyCacheTtlMs = 5 * 60 * 1000;

function responseCacheTtl(res: Response, empty: boolean): number {
  const control = res.headers.get('cache-control') ?? '';
  if (/(?:^|,)\s*(?:no-store|no-cache|private)(?:\s|=|,|$)/i.test(control)) return 0;
  let ttl = empty ? emptyCacheTtlMs : cacheTtlMs;
  const maxAge = /(?:^|,)\s*s-maxage\s*=\s*"?(\d+)/i.exec(control)
    ?? /(?:^|,)\s*max-age\s*=\s*"?(\d+)/i.exec(control);
  const now = Date.now();
  const responseDate = Date.parse(res.headers.get('date') ?? '');
  const apparentAge = Number.isFinite(responseDate) ? Math.max(0, now - responseDate) : 0;
  const age = Math.max(apparentAge, (Number(res.headers.get('age')) || 0) * 1000);
  if (maxAge) {
    ttl = Math.min(ttl, Number(maxAge[1]) * 1000 - age);
  } else if (res.headers.has('expires')) {
    const expires = Date.parse(res.headers.get('expires')!);
    // Treat an invalid Expires value as already expired.
    const origin = Number.isFinite(responseDate) ? responseDate : now;
    ttl = Number.isFinite(expires) ? Math.min(ttl, expires - origin - age) : 0;
  }
  return Math.max(0, ttl);
}

/** Shared Firestore cache; pending requests are also coalesced per instance. */
export class LastFmCatalog {
  private readonly pending = new Map<string, Promise<string[]>>();

  constructor(private readonly firestore: Firestore) {}

  async getStrings(
    method: LastFmMethod,
    artistName: string,
    apiKey: string,
    parse: (data: unknown) => string[],
  ): Promise<string[]> {
    const artist = artistName.trim().normalize('NFC').replace(/\s+/g, ' ');
    // Version the parsed representation; never put credentials in the key/data.
    const key = createHash('sha256')
      .update(JSON.stringify(['v1', method, artist.toLowerCase()]))
      .digest('hex');
    const existing = this.pending.get(key);
    if (existing) return existing;

    const request = this.load(key, method, artist, apiKey, parse);
    this.pending.set(key, request);
    try {
      return await request;
    } finally {
      this.pending.delete(key);
    }
  }

  private async load(
    key: string,
    method: LastFmMethod,
    artistName: string,
    apiKey: string,
    parse: (data: unknown) => string[],
  ): Promise<string[]> {
    const ref = this.firestore.doc(`lastfm_cache/${key}`);
    const cached = (await ref.get()).data();
    if (
      cached?.expiresAt instanceof Timestamp
      && cached.expiresAt.toMillis() > Date.now()
      && Array.isArray(cached.values)
      && cached.values.every((value: unknown) => typeof value === 'string')
    ) {
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
      url.searchParams.set('limit', String(catalogSearchMaxLimit));
    }

    let response: Response;
    try {
      response = await fetch(url.toString(), {
        headers: { 'User-Agent': 'MusiLink/1.0' },
        signal: AbortSignal.timeout(requestTimeoutMs),
      });
    } catch (error: unknown) {
      logger.warn('Last.fm request failed before receiving a response', {
        reason: error instanceof Error ? error.name : 'unknown',
      });
      throw new HttpsError('unavailable', 'Last.fm is temporarily unavailable');
    }
    if (!response.ok) {
      throw new HttpsError(
        response.status === 429 ? 'resource-exhausted' : 'unavailable',
        'Last.fm request failed',
      );
    }
    let data: unknown;
    try {
      data = await response.json();
    } catch {
      throw new HttpsError('unavailable', 'Last.fm returned an invalid response');
    }
    // Last.fm also reports API errors inside otherwise successful HTTP responses.
    if (isRecord(data) && data.error !== undefined) {
      throw new HttpsError(
        Number(data.error) === 29 ? 'resource-exhausted' : 'unavailable',
        'Last.fm request failed',
      );
    }
    // Parsers reject malformed bodies. Only successful results (including a
    // genuinely empty list) may enter either backend or client caches.
    const values = parse(data);
    const ttl = responseCacheTtl(response, values.length === 0);
    if (ttl > 0) {
      try {
        await ref.set({ values, expiresAt: Timestamp.fromMillis(Date.now() + ttl) });
      } catch {
        logger.warn('Unable to cache Last.fm response', { method });
      }
    }
    return values;
  }
}

export const lastFmCatalog = new LastFmCatalog(db);
