import { normalizeGenreName } from './genre_normalizer';

const maxSpotifyGenresPerArtist = 5;
const maxLastFmGenresPerArtist = 2;
const minLastFmTagCount = 10;

const lastFmGenreKeywords = [
  'afrobeat',
  'afrobeats',
  'alternative',
  'ambient',
  'americana',
  'bachata',
  'bluegrass',
  'blues',
  'bebop',
  'classical',
  'corrido',
  'corridos',
  'country',
  'dance',
  'dancehall',
  'disco',
  'drill',
  'dub',
  'dubstep',
  'electronic',
  'emo',
  'experimental',
  'flamenco',
  'folk',
  'funk',
  'fusion',
  'gospel',
  'grunge',
  'hardcore',
  'hip hop',
  'house',
  'indie',
  'industrial',
  'jazz',
  'latin',
  'metal',
  'new wave',
  'opera',
  'pop',
  'post punk',
  'punk',
  'r&b',
  'regional mexicano',
  'reggae',
  'reggaeton',
  'rock',
  'salsa',
  'shoegaze',
  'ska',
  'soul',
  'synthpop',
  'techno',
  'trance',
  'trap',
];

function hasLastFmGenreKeyword(value: string): boolean {
  return lastFmGenreKeywords.some((keyword) => {
    if (value === keyword) return true;
    return value.startsWith(`${keyword} `) ||
      value.endsWith(` ${keyword}`) ||
      value.includes(` ${keyword} `);
  });
}

export function normalizeSpotifyGenres(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  const genres = new Map<string, string>();
  for (const value of values) {
    if (typeof value !== 'string') continue;
    const normalized = normalizeGenreName(value);
    if (!normalized) continue;
    genres.set(normalized, normalized);
    if (genres.size >= maxSpotifyGenresPerArtist) break;
  }
  return [...genres.values()];
}

export function normalizeLastFmTags(tags: Array<{ name?: string; count?: number | string }>): string[] {
  const genres = new Map<string, string>();
  for (const tag of tags) {
    const count = Number(tag.count ?? 0);
    if (!tag.name || count < minLastFmTagCount) continue;
    const normalized = normalizeGenreName(tag.name);
    if (!normalized || !hasLastFmGenreKeyword(normalized)) continue;
    genres.set(normalized, normalized);
    if (genres.size >= maxLastFmGenresPerArtist) break;
  }
  return [...genres.values()];
}
