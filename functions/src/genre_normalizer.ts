const genreAliases: Record<string, string> = {
  'alt rock': 'alternative rock',
  alternative: 'alternative',
  'alternative music': 'alternative',
  'corridos belicos': 'corridos belicos',
  'drum and bass': 'drum and bass',
  dnb: 'drum and bass',
  edm: 'electronic',
  electro: 'electronic',
  electronica: 'electronic',
  'electronic music': 'electronic',
  hiphop: 'hip hop',
  'hip hop music': 'hip hop',
  rap: 'hip hop',
  'rhythm and blues': 'r&b',
  rnb: 'r&b',
  'singer songwriter': 'singer-songwriter',
  'synth pop': 'synthpop',
};

const blockedGenreTags = new Set([
  '00s', '10s', '20s', '60s', '70s', '80s', '90s',
  'american', 'australian', 'belgian', 'brazilian', 'british', 'canadian',
  'chilean', 'chinese', 'colombian', 'danish', 'dutch', 'english', 'favorite',
  'favorites', 'favourite', 'female vocalists', 'finnish', 'french', 'german',
  'greek', 'icelandic', 'irish', 'italian', 'japanese', 'korean',
  'male vocalists', 'mexican', 'mexico', 'new zealand', 'norwegian', 'polish',
  'portuguese', 'puerto rican', 'puerto rico', 'romanian', 'russian',
  'scottish', 'seen live', 'spanish', 'spain', 'swedish', 'turkish', 'uk',
  'ukrainian', 'usa', 'vocalists', 'welsh',
]);

const decadeOrYearPattern = /^(?:[0-9]{2}s|[12][0-9]{3}s?)$/;

export function normalizeGenreName(value: string): string | undefined {
  const key = value
    .trim()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\br\s*&\s*b\b/g, 'rnb')
    .replace(/&/g, ' and ')
    .replace(/[-_/]+/g, ' ')
    .replace(/[^a-z0-9&]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  if (!key) return undefined;
  const normalized = genreAliases[key] ?? key;
  if (normalized.length < 2
      || blockedGenreTags.has(normalized)
      || decadeOrYearPattern.test(normalized)
      || normalized.includes('seen live')
      || normalized.includes('favorite')) {
    return undefined;
  }
  return normalized;
}
