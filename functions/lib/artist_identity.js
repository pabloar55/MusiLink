"use strict";
// Identidad de artista compartida por la escritura del perfil musical y las
// recomendaciones. Misma regla que `lib/utils/artist_identity.dart`.
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeArtistIdentityName = normalizeArtistIdentityName;
exports.artistIdentityKey = artistIdentityKey;
exports.normalizedStoredArtistKey = normalizedStoredArtistKey;
exports.artistIdentitiesMatch = artistIdentitiesMatch;
const artistDiacriticGroups = {
    a: 'áàäâãåāăąæ',
    c: 'çćčĉċ',
    d: 'ďđð',
    e: 'éèëêēĕėęě',
    g: 'ğĝġģ',
    h: 'ĥħ',
    i: 'íìïîīĭįı',
    j: 'ĵ',
    k: 'ķ',
    l: 'ĺļľŀł',
    n: 'ñńņňŉŋ',
    o: 'óòöôõōŏőøœ',
    r: 'ŕŗř',
    s: 'śşšŝșß',
    t: 'ťţŧț',
    u: 'úùüûūŭůűų',
    w: 'ŵ',
    y: 'ýÿŷ',
    z: 'źżž',
};
const artistDiacriticReplacements = new Map(Object.entries(artistDiacriticGroups)
    .flatMap(([replacement, characters]) => [...characters].map((character) => [character, replacement])));
function normalizeArtistIdentityName(value) {
    const folded = [...value.trim().toLowerCase()]
        .map((character) => artistDiacriticReplacements.get(character) ?? character)
        .join('');
    return folded
        .replace(/['’]/g, '')
        .replace(/&/g, ' and ')
        .replace(/[-_/.,:;!?()[\]{}"“”+*=|\\]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}
/** Clave de Spotify si hay id; si no, el nombre normalizado. */
function artistIdentityKey(name, spotifyId) {
    return spotifyId
        ? `spotify:${spotifyId}`
        : `name:${normalizeArtistIdentityName(name)}`;
}
/** Normaliza una clave guardada; `undefined` si no es una clave válida. */
function normalizedStoredArtistKey(value) {
    const trimmed = value.trim();
    if (trimmed.startsWith('spotify:')) {
        const spotifyId = trimmed.slice('spotify:'.length).trim();
        return spotifyId ? `spotify:${spotifyId}` : undefined;
    }
    if (trimmed.startsWith('name:')) {
        const name = normalizeArtistIdentityName(trimmed.slice('name:'.length));
        return name ? `name:${name}` : undefined;
    }
    return undefined;
}
/**
 * Dos claves de Spotify deciden por sí solas; si falta alguna, se compara el
 * nombre normalizado.
 */
function artistIdentitiesMatch(left, right) {
    const leftHasSpotifyId = left.key.startsWith('spotify:');
    const rightHasSpotifyId = right.key.startsWith('spotify:');
    if (leftHasSpotifyId && rightHasSpotifyId)
        return left.key === right.key;
    return left.normalizedName === right.normalizedName;
}
//# sourceMappingURL=artist_identity.js.map