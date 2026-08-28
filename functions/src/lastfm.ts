import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { isRecord, parseLastFmSearchRequest } from './catalog_request';

const lastFmApiKey = defineSecret('LASTFM_API_KEY');

const collabPattern = /(&|feat\.?|ft\.?)/i;
const lastFmRequestTimeoutMs = 5_000;

async function fetchLastFm(input: string): Promise<Response> {
  try {
    return await fetch(input, { signal: AbortSignal.timeout(lastFmRequestTimeoutMs) });
  } catch (error: unknown) {
    logger.warn('Last.fm request failed before receiving a response', {
      reason: error instanceof Error ? error.name : 'unknown',
    });
    throw new HttpsError('unavailable', 'Last.fm is temporarily unavailable');
  }
}

export const getSimilarArtists = onCall(
  {
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [lastFmApiKey],
  },
  async (request): Promise<string[]> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Login required');

    const { value: artistName, limit } = parseLastFmSearchRequest(request.data);

    const url = new URL('https://ws.audioscrobbler.com/2.0/');
    url.searchParams.set('method', 'artist.getSimilar');
    url.searchParams.set('artist', artistName);
    url.searchParams.set('api_key', lastFmApiKey.value());
    url.searchParams.set('format', 'json');
    url.searchParams.set('limit', String(limit));
    url.searchParams.set('autocorrect', '1');

    const res = await fetchLastFm(url.toString());
    if (!res.ok) {
      logger.error('Last.fm getSimilar failed', { status: res.status, artistName });
      if (res.status === 429) {
        throw new HttpsError('resource-exhausted', 'Last.fm rate limit reached');
      }
      throw new HttpsError('internal', 'Last.fm request failed');
    }

    const data: unknown = await res.json();
    const artists = isRecord(data) && isRecord(data.similarartists)
      ? data.similarartists.artist
      : undefined;
    if (!Array.isArray(artists)) return [];

    return artists
      .filter(isRecord)
      .map((artist) => typeof artist.name === 'string' ? artist.name : '')
      .filter((name) => name && !collabPattern.test(name))
      .slice(0, limit);
  },
);
