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
  });
}
