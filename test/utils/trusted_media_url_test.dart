import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/trusted_media_url.dart';

void main() {
  group('trustedSpotifyImageUrl', () {
    test('acepta únicamente imágenes canónicas del CDN de Spotify', () {
      const valid =
          'https://i.scdn.co/image/ab67616d0000b27371dfaeb7a1930cf0ad245854';

      expect(trustedSpotifyImageUrl(valid), valid);
      expect(
        trustedSpotifyImageUrl('https://tracking.example/song.jpg'),
        isEmpty,
      );
      expect(
        trustedSpotifyImageUrl('https://i.scdn.co.evil.example/image/test'),
        isEmpty,
      );
      expect(
        trustedSpotifyImageUrl('https://i.scdn.co/image/test?tracker=1'),
        isEmpty,
      );
    });
  });

  group('trustedProfilePhotoUrl', () {
    test('acepta únicamente fotos del bucket y ruta de perfiles', () {
      const valid =
          'https://firebasestorage.googleapis.com/v0/b/'
          'musi-link-e7759.firebasestorage.app/o/'
          'profile_photos%2Falice?alt=media&token=test-token';

      expect(trustedProfilePhotoUrl(valid), valid);
      expect(
        trustedProfilePhotoUrl('https://tracking.example/alice.jpg'),
        isEmpty,
      );
      expect(
        trustedProfilePhotoUrl(
          'https://firebasestorage.googleapis.com.evil.example/v0/b/'
          'musi-link-e7759.firebasestorage.app/o/'
          'profile_photos%2Falice?alt=media&token=test-token',
        ),
        isEmpty,
      );
    });
  });
}
