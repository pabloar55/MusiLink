import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { isRecord } from './catalog_request';

type LastFmMethod = 'artist.getSimilar' | 'artist.getTopTags';
const requestTimeoutMs = 5_000;

export async function fetchLastFm(
  method: LastFmMethod,
  artistName: string,
  apiKey: string,
  limit = 10,
): Promise<unknown> {
  const url = new URL('https://ws.audioscrobbler.com/2.0/');
  url.searchParams.set('method', method);
  url.searchParams.set('artist', artistName);
  url.searchParams.set('api_key', apiKey);
  url.searchParams.set('format', 'json');
  url.searchParams.set('autocorrect', '1');
  if (method === 'artist.getSimilar') {
    url.searchParams.set('limit', String(limit));
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
  return data;
}
