import 'package:musi_link/models/artist.dart';

const artistIdentityVersion = 1;

const _latinDiacriticGroups = <String, String>{
  'a': 'áàäâãåāăąæ',
  'c': 'çćčĉċ',
  'd': 'ďđð',
  'e': 'éèëêēĕėęě',
  'g': 'ğĝġģ',
  'h': 'ĥħ',
  'i': 'íìïîīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉŋ',
  'o': 'óòöôõōŏőøœ',
  'r': 'ŕŗř',
  's': 'śşšŝșß',
  't': 'ťţŧț',
  'u': 'úùüûūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final Map<String, String> _latinDiacriticReplacements = {
  for (final entry in _latinDiacriticGroups.entries)
    for (final character in entry.value.split('')) character: entry.key,
};

final _artistNameSeparators = RegExp(r'''[-_/.,:;!?()[\]{}"“”+*=|\\]+''');
final _artistNameSpaces = RegExp(r'\s+');

/// Produces a stable fallback identity without discarding non-Latin scripts.
String normalizeArtistIdentityName(String value) {
  final folded = StringBuffer();
  for (final rune in value.trim().toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    folded.write(_latinDiacriticReplacements[character] ?? character);
  }

  return folded
      .toString()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll('&', ' and ')
      .replaceAll(_artistNameSeparators, ' ')
      .replaceAll(_artistNameSpaces, ' ')
      .trim();
}

String artistIdentityKey({required String name, String? spotifyId}) {
  final cleanedSpotifyId = spotifyId?.trim();
  if (cleanedSpotifyId != null && cleanedSpotifyId.isNotEmpty) {
    return 'spotify:$cleanedSpotifyId';
  }
  return 'name:${normalizeArtistIdentityName(name)}';
}

List<String> artistIdentityKeys(Iterable<Artist> artists) => artists
    .map(
      (artist) =>
          artistIdentityKey(name: artist.name, spotifyId: artist.spotifyId),
    )
    .toList(growable: false);

bool isSpotifyArtistIdentityKey(String value) =>
    value.trim().startsWith('spotify:') &&
    value.trim().length > 'spotify:'.length;

/// Misma regla que `artistIdentitiesMatch` en el backend: dos claves de
/// Spotify deciden por sí solas; si falta alguna, se compara el nombre
/// normalizado.
bool artistIdentitiesMatch({
  required String leftName,
  required String leftKey,
  required String rightName,
  required String rightKey,
}) {
  if (isSpotifyArtistIdentityKey(leftKey) &&
      isSpotifyArtistIdentityKey(rightKey)) {
    return leftKey == rightKey;
  }
  return normalizeArtistIdentityName(leftName) ==
      normalizeArtistIdentityName(rightName);
}

/// Si [left] y [right] son el mismo artista según [artistIdentitiesMatch].
bool isSameArtist(Artist left, Artist right) => artistIdentitiesMatch(
  leftName: left.name,
  leftKey: artistIdentityKey(name: left.name, spotifyId: left.spotifyId),
  rightName: right.name,
  rightKey: artistIdentityKey(name: right.name, spotifyId: right.spotifyId),
);

/// Artistas distintos entre sí según [isSameArtist], con consultas en tiempo
/// constante.
class ArtistIdentitySet {
  ArtistIdentitySet([Iterable<Artist> artists = const []]) {
    artists.forEach(add);
  }

  final _spotifyKeys = <String>{};
  final _names = <String>{};
  final _namesWithoutSpotifyKey = <String>{};

  /// Si algún miembro es el mismo artista que [artist].
  bool contains(Artist artist) {
    final key = artistIdentityKey(
      name: artist.name,
      spotifyId: artist.spotifyId,
    );
    final name = normalizeArtistIdentityName(artist.name);
    if (isSpotifyArtistIdentityKey(key)) {
      return _spotifyKeys.contains(key) ||
          _namesWithoutSpotifyKey.contains(name);
    }
    return _names.contains(name);
  }

  /// Añade [artist] salvo que ya esté; devuelve si lo ha añadido.
  bool add(Artist artist) {
    if (contains(artist)) return false;
    final key = artistIdentityKey(
      name: artist.name,
      spotifyId: artist.spotifyId,
    );
    final name = normalizeArtistIdentityName(artist.name);
    _names.add(name);
    if (isSpotifyArtistIdentityKey(key)) {
      _spotifyKeys.add(key);
    } else {
      _namesWithoutSpotifyKey.add(name);
    }
    return true;
  }
}
