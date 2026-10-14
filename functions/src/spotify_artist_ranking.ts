// Reglas puras para elegir y ordenar los artistas de una búsqueda en Spotify:
// normalización del nombre, puntuación, filtrado, ordenación y límite. Las
// llamadas externas y el enriquecimiento de géneros quedan en `spotify.ts`.

export interface SpotifyArtistItem {
  id: string;
  name: string;
  genres?: string[];
  images?: Array<{ url: string }>;
  popularity?: number;
  followers?: { total?: number };
}

interface RankedArtist {
  item: SpotifyArtistItem;
  nameKey: string;
  score: number;
}

export function normalizeArtistName(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/'/g, '')
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function scoreArtistMatch(
  item: SpotifyArtistItem,
  queryKey: string,
  queryTokens: string[],
): number {
  const nameKey = normalizeArtistName(item.name ?? '');
  if (!nameKey) return Number.NEGATIVE_INFINITY;

  let score = 0;
  if (nameKey === queryKey) {
    score += 350;
  } else if (nameKey.startsWith(`${queryKey} `)) {
    score += 300;
  } else if (nameKey.includes(queryKey)) {
    score += 180;
  } else {
    const nameTokens = new Set(nameKey.split(' '));
    const matchingTokens = queryTokens.filter((token) => nameTokens.has(token)).length;
    if (matchingTokens === 0) score -= 200;
    score += (matchingTokens / Math.max(queryTokens.length, 1)) * 120;
  }

  const popularity = Math.max(0, Math.min(item.popularity ?? 0, 100));
  const followers = Math.max(0, item.followers?.total ?? 0);
  const hasImage = Boolean(item.images?.[0]?.url);
  const hasGenres = Boolean(item.genres?.length);

  score += popularity * 9;
  score += Math.log10(followers + 1) * 45;
  if (hasImage) score += 30;
  if (hasGenres) score += 20;

  if (nameKey !== queryKey && popularity < 10 && followers < 10_000) score -= 250;
  if (!hasImage && popularity < 20) score -= 80;

  return score;
}

/**
 * Devuelve como máximo `limit` artistas con puntuación positiva, de mayor a
 * menor puntuación. Los empates conservan el orden de Spotify. Si algún
 * candidato coincide exactamente con la búsqueda, se descartan los que no
 * contienen la búsqueda en su nombre salvo que puntúen al menos 500.
 */
export function rankSpotifyArtists(
  items: readonly SpotifyArtistItem[],
  query: string,
  limit: number,
): SpotifyArtistItem[] {
  const queryKey = normalizeArtistName(query);
  const queryTokens = queryKey.split(' ').filter(Boolean);

  const rankedItems: RankedArtist[] = items.map((item) => ({
    item,
    nameKey: normalizeArtistName(item.name ?? ''),
    score: scoreArtistMatch(item, queryKey, queryTokens),
  }));
  const hasExactMatch = rankedItems.some(({ nameKey }) => nameKey === queryKey);

  return rankedItems
    .filter(({ nameKey, score }) => {
      if (score <= 0) return false;
      if (!hasExactMatch) return true;
      return nameKey === queryKey ||
        nameKey.startsWith(`${queryKey} `) ||
        nameKey.includes(queryKey) ||
        score >= 500;
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
    .map(({ item }) => item);
}
