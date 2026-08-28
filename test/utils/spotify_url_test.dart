import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/spotify_url.dart';

void main() {
  test('acepta una URL canónica de canción de Spotify', () {
    const value = 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC';

    expect(parseSpotifyTrackUri(value)?.toString(), value);
  });

  test('rechaza URLs que no sean una canción canónica de Spotify', () {
    for (final value in [
      'https://phishing.example/track/4uLU6hMCjMI75M1A2tKUQC',
      'https://open.spotify.com.evil.example/track/4uLU6hMCjMI75M1A2tKUQC',
      'https://open.spotify.com@evil.example/track/4uLU6hMCjMI75M1A2tKUQC',
      'https://open.spotify.com/track/short-id',
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=attacker',
      'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC/extra',
      '',
    ]) {
      expect(parseSpotifyTrackUri(value), isNull, reason: value);
    }
  });
}
