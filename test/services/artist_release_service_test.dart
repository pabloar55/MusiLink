import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/artist_release.dart';
import 'package:musi_link/services/artist_release_service.dart';

String _id(String char) => char * 22;

Map<String, Object?> _release(
  String char,
  String releaseDate, {
  String type = 'single',
}) => {
  'id': _id(char),
  'name': 'Release $char',
  'type': type,
  'releaseDate': releaseDate,
  'imageUrl': 'https://i.scdn.co/image/abc$char',
  'announce': true,
};

void main() {
  final now = DateTime(2026, 11, 7, 18);

  group('ArtistReleaseService.weeklyReleases', () {
    test('keeps the last seven days, newest first, albums first', () {
      final releases = ArtistReleaseService.weeklyReleases(
        {
          _id('r'): [
            _release('a', '2026-11-07'),
            _release('b', '2026-11-06'),
            _release('c', '2026-11-06', type: 'album'),
            _release('d', '2026-11-01'),
            _release('o', '2026-10-31'),
            _release('f', '2026-11-09'),
          ],
        },
        {_id('r'): 'Rosalía'},
        now,
      );

      expect(releases.map((release) => release.id[0]), ['a', 'c', 'b', 'd']);
      expect(releases.first.artistNames, ['Rosalía']);
      expect(releases[1].type, ArtistReleaseType.album);
      expect(
        releases.first.spotifyUri.toString(),
        'https://open.spotify.com/album/${_id('a')}',
      );
    });

    test('shows a collaboration between followed artists once', () {
      final releases = ArtistReleaseService.weeklyReleases(
        {
          _id('r'): [_release('a', '2026-11-06')],
          _id('q'): [_release('a', '2026-11-06')],
        },
        {_id('r'): 'Rosalía', _id('q'): 'Quevedo'},
        now,
      );

      expect(releases, hasLength(1));
      expect(releases.single.artistNames, ['Rosalía', 'Quevedo']);
    });

    test('ignores malformed entries and untrusted images', () {
      final releases = ArtistReleaseService.weeklyReleases(
        {
          _id('r'): [
            {
              ..._release('a', '2026-11-06'),
              'imageUrl': 'https://evil.example',
            },
            {..._release('b', '2026-11-06'), 'id': 'short'},
            {..._release('c', '2026-11'), 'type': 'single'},
            {..._release('d', '2026-11-06'), 'type': 'compilation'},
            'raw',
          ],
          _id('x'): 'not a list',
        },
        {_id('r'): 'Rosalía', _id('x'): 'Otro'},
        now,
      );

      expect(releases, hasLength(1));
      expect(releases.single.imageUrl, isEmpty);
    });
  });

  test('followedArtistNames keeps unique artists with a Spotify id', () {
    expect(
      ArtistReleaseService.followedArtistNames([
        Artist(
          name: 'Rosalía',
          imageUrl: '',
          genres: const [],
          spotifyId: _id('r'),
        ),
        const Artist(name: 'Sin id', imageUrl: '', genres: []),
        Artist(
          name: 'Duplicada',
          imageUrl: '',
          genres: const [],
          spotifyId: _id('r'),
        ),
        const Artist(
          name: 'Inválido',
          imageUrl: '',
          genres: [],
          spotifyId: 'x',
        ),
      ]),
      {_id('r'): 'Rosalía'},
    );
  });
}
