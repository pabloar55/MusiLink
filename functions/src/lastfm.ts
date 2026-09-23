import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { db } from './firebase';
import { consumeCatalogSearchQuota } from './rate_limits';
import { isRecord, parseLastFmSearchRequest } from './catalog_request';
import { fetchLastFm } from './lastfm_request';

const lastFmApiKey = defineSecret('LASTFM_API_KEY');

const collabPattern = /(&|feat\.?|ft\.?)/i;

export const getSimilarArtists = onCall(
  {
    region: 'europe-southwest1',
    enforceAppCheck: true,
    secrets: [lastFmApiKey],
  },
  async (request): Promise<string[]> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Login required');

    const { value: artistName, limit } = parseLastFmSearchRequest(request.data);
    await consumeCatalogSearchQuota(db, request.auth.uid, 'lastFmSimilar');

    const data = await fetchLastFm('artist.getSimilar', artistName, lastFmApiKey.value(), limit);
    const items = isRecord(data) && isRecord(data.similarartists)
      ? data.similarartists.artist
      : undefined;
    if (!Array.isArray(items) || items.some((artist) => (
      !isRecord(artist) || typeof artist.name !== 'string' || !artist.name.trim()
    ))) {
      throw new HttpsError('unavailable', 'Last.fm returned an invalid artist list');
    }
    return items
      .filter(isRecord)
      .map((artist) => typeof artist.name === 'string' ? artist.name : '')
      .filter((name) => name && !collabPattern.test(name))
      .slice(0, limit);
  },
);
