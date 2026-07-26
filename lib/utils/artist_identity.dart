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
