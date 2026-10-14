"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeSpotifyGenres = normalizeSpotifyGenres;
exports.normalizeLastFmTags = normalizeLastFmTags;
const genre_normalizer_1 = require("./genre_normalizer");
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
function hasLastFmGenreKeyword(value) {
    return lastFmGenreKeywords.some((keyword) => {
        if (value === keyword)
            return true;
        return value.startsWith(`${keyword} `) ||
            value.endsWith(` ${keyword}`) ||
            value.includes(` ${keyword} `);
    });
}
function normalizeSpotifyGenres(values) {
    if (!Array.isArray(values))
        return [];
    const genres = new Map();
    for (const value of values) {
        if (typeof value !== 'string')
            continue;
        const normalized = (0, genre_normalizer_1.normalizeGenreName)(value);
        if (!normalized)
            continue;
        genres.set(normalized, normalized);
        if (genres.size >= maxSpotifyGenresPerArtist)
            break;
    }
    return [...genres.values()];
}
function normalizeLastFmTags(tags) {
    const genres = new Map();
    for (const tag of tags) {
        const count = Number(tag.count ?? 0);
        if (!tag.name || count < minLastFmTagCount)
            continue;
        const normalized = (0, genre_normalizer_1.normalizeGenreName)(tag.name);
        if (!normalized || !hasLastFmGenreKeyword(normalized))
            continue;
        genres.set(normalized, normalized);
        if (genres.size >= maxLastFmGenresPerArtist)
            break;
    }
    return [...genres.values()];
}
//# sourceMappingURL=catalog_genres.js.map