import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/utils/artist_identity.dart';

void main() {
  group('artist identity', () {
    test('prioriza spotifyId cuando existe', () {
      expect(
        artistIdentityKey(name: 'Radiohead', spotifyId: ' 4Z8W4fKe '),
        'spotify:4Z8W4fKe',
      );
    });

    test('genera fallback determinista con nombre normalizado', () {
      expect(artistIdentityKey(name: '  Beyoncé  '), 'name:beyonce');
      expect(artistIdentityKey(name: 'AC/DC'), 'name:ac dc');
      expect(
        artistIdentityKey(name: 'Florence & The Machine'),
        'name:florence and the machine',
      );
    });

    test('conserva alfabetos no latinos en el fallback', () {
      expect(artistIdentityKey(name: '宇多田ヒカル'), 'name:宇多田ヒカル');
    });

    test('genera claves alineadas con la lista de artistas', () {
      expect(
        artistIdentityKeys(const [
          Artist(
            name: 'Radiohead',
            imageUrl: '',
            genres: [],
            spotifyId: 'radiohead-id',
          ),
          Artist(name: 'Beyoncé', imageUrl: '', genres: []),
        ]),
        ['spotify:radiohead-id', 'name:beyonce'],
      );
    });

    test('el spotifyId decide solo cuando ambos lo tienen', () {
      const nirvanaUs = Artist(
        name: 'Nirvana',
        imageUrl: '',
        genres: [],
        spotifyId: 'us',
      );
      const nirvanaUk = Artist(
        name: 'Nirvana',
        imageUrl: '',
        genres: [],
        spotifyId: 'uk',
      );
      const lastFmNirvana = Artist(name: 'nirvana', imageUrl: '', genres: []);

      expect(isSameArtist(nirvanaUs, nirvanaUk), isFalse);
      expect(isSameArtist(lastFmNirvana, nirvanaUs), isTrue);
      expect(isSameArtist(lastFmNirvana, nirvanaUk), isTrue);
      expect(
        isSameArtist(
          const Artist(name: 'Βανδή', imageUrl: '', genres: []),
          const Artist(name: 'Ρουβάς', imageUrl: '', genres: []),
        ),
        isFalse,
      );
    });

    test('ArtistIdentitySet aplica la misma regla que isSameArtist', () {
      const artists = [
        Artist(name: 'Nirvana', imageUrl: '', genres: [], spotifyId: 'us'),
        Artist(name: 'Nirvana', imageUrl: '', genres: [], spotifyId: 'uk'),
        Artist(name: 'nirvana', imageUrl: '', genres: []),
        Artist(name: 'Beyoncé', imageUrl: '', genres: []),
        Artist(name: 'Beyonce', imageUrl: '', genres: [], spotifyId: 'b'),
        Artist(name: 'Other', imageUrl: '', genres: [], spotifyId: 'b'),
        Artist(name: 'Βανδή', imageUrl: '', genres: []),
        Artist(name: 'Ρουβάς', imageUrl: '', genres: []),
      ];

      for (var start = 0; start < artists.length; start++) {
        final members = <Artist>[];
        final set = ArtistIdentitySet();
        for (final artist in [...artists.skip(start), ...artists.take(start)]) {
          final expected = !members.any((m) => isSameArtist(m, artist));
          expect(set.add(artist), expected, reason: artist.name);
          if (expected) members.add(artist);
        }
      }
    });
  });
}
