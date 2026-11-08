import 'package:musi_link/utils/trusted_media_url.dart';

enum ArtistReleaseType { single, album }

final RegExp _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');
final RegExp _isoDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Lanzamiento reciente de un artista seguido.
///
/// Contrato: elementos de `artist_releases/{spotifyId}.recentReleases`,
/// escritos por `functions/src/artist_releases.ts` (`StoredRelease`).
class ArtistRelease {
  const ArtistRelease({
    required this.id,
    required this.name,
    required this.type,
    required this.releaseDate,
    required this.imageUrl,
    required this.artistIds,
    required this.artistNames,
  });

  final String id;
  final String name;
  final ArtistReleaseType type;

  /// Fecha de publicación (solo día), a medianoche local.
  final DateTime releaseDate;
  final String imageUrl;

  /// Artistas seguidos que firman el lanzamiento (varios en colaboraciones).
  final List<String> artistIds;
  final List<String> artistNames;

  Uri get spotifyUri => Uri.parse('https://open.spotify.com/album/$id');

  ArtistRelease withArtist(String artistId, String artistName) {
    if (artistIds.contains(artistId)) return this;
    return ArtistRelease(
      id: id,
      name: name,
      type: type,
      releaseDate: releaseDate,
      imageUrl: imageUrl,
      artistIds: [...artistIds, artistId],
      artistNames: [...artistNames, artistName],
    );
  }

  /// Parses untrusted persisted data without throwing.
  static ArtistRelease? tryFromMap(
    Object? value, {
    required String artistId,
    required String artistName,
  }) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final type = switch (value['type']) {
      'single' => ArtistReleaseType.single,
      'album' => ArtistReleaseType.album,
      _ => null,
    };
    final releaseDate = value['releaseDate'];
    final imageUrl = value['imageUrl'];
    if (id is! String || !_spotifyId.hasMatch(id)) return null;
    if (name is! String || name.trim().isEmpty || type == null) return null;
    if (releaseDate is! String) return null;
    final match = _isoDay.firstMatch(releaseDate);
    if (match == null) return null;
    final date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );

    return ArtistRelease(
      id: id,
      name: name.trim(),
      type: type,
      releaseDate: date,
      imageUrl: imageUrl is String ? trustedSpotifyImageUrl(imageUrl) : '',
      artistIds: [artistId],
      artistNames: [artistName],
    );
  }
}
