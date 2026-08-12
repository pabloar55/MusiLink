import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/last_fm_service.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/services/spotify_cloud_service.dart';

class MockSpotifyCloudService extends Mock implements SpotifyCloudService {}

class MockLastFmService extends Mock implements LastFmService {}

void main() {
  group('MusicCatalogService.getTopGenresFromArtists', () {
    late MusicCatalogService service;

    setUp(() {
      service = MusicCatalogService(
        MockSpotifyCloudService(),
        MockLastFmService(),
      );
    });

    test('normalizes aliases, removes noisy tags, and deduplicates counts', () {
      final genres = service.getTopGenresFromArtists(const [
        Artist(
          name: 'Artist A',
          imageUrl: '',
          genres: ['Hip-Hop', 'Canadian', 'seen live', 'R&B'],
        ),
        Artist(
          name: 'Artist B',
          imageUrl: '',
          genres: ['rap', 'rhythm and blues', '80s', 'electro'],
        ),
      ], 10);

      expect(genres.map((genre) => genre.name), [
        'hip hop',
        'r&b',
        'electronic',
      ]);
      expect(genres.map((genre) => genre.count), [2, 2, 1]);
    });

    test('honors the requested genre limit after normalization', () {
      final genres = service.getTopGenresFromArtists(const [
        Artist(name: 'Artist A', imageUrl: '', genres: ['rock', 'pop', 'jazz']),
      ], 2);

      expect(genres.map((genre) => genre.name), ['rock', 'pop']);
    });
  });

  group('MusicCatalogService.getRelatedArtists', () {
    late MockSpotifyCloudService spotify;
    late MockLastFmService lastFm;
    late MusicCatalogService service;

    setUp(() {
      spotify = MockSpotifyCloudService();
      lastFm = MockLastFmService();
      service = MusicCatalogService(spotify, lastFm);
    });

    test('reutiliza la caché para nombres equivalentes', () async {
      const related = [Artist(name: 'Similar', imageUrl: '', genres: [])];
      when(
        () => lastFm.getSimilarArtists('Radiohead'),
      ).thenAnswer((_) async => related);

      final first = await service.getRelatedArtists('  Radiohead  ');
      final second = await service.getRelatedArtists('radiohead');

      expect(first, related);
      expect(second, related);
      verify(() => lastFm.getSimilarArtists('Radiohead')).called(1);
    });

    test('comparte peticiones simultáneas para el mismo artista', () async {
      final result = Completer<List<Artist>>();
      when(
        () => lastFm.getSimilarArtists('Muse'),
      ).thenAnswer((_) => result.future);

      final first = service.getRelatedArtists('Muse');
      final second = service.getRelatedArtists(' muse ');
      result.complete(const [
        Artist(name: 'Similar', imageUrl: '', genres: []),
      ]);

      final results = await Future.wait([first, second]);
      expect(results[0], same(results[1]));
      verify(() => lastFm.getSimilarArtists('Muse')).called(1);
    });

    test('no ejecuta más de tres consultas de Last.fm a la vez', () async {
      var activeRequests = 0;
      var maxActiveRequests = 0;
      final requests = <String, Completer<List<Artist>>>{};
      when(() => lastFm.getSimilarArtists(any())).thenAnswer((invocation) {
        final name = invocation.positionalArguments.first as String;
        final completer = Completer<List<Artist>>();
        requests[name] = completer;
        activeRequests++;
        if (activeRequests > maxActiveRequests) {
          maxActiveRequests = activeRequests;
        }
        return completer.future.whenComplete(() => activeRequests--);
      });

      final futures = [
        for (var i = 0; i < 5; i++) service.getRelatedArtists('Artist $i'),
      ];
      await Future<void>.delayed(Duration.zero);

      expect(requests.length, 3);
      requests['Artist 0']!.complete(const []);
      await Future<void>.delayed(Duration.zero);
      expect(requests.length, 4);
      requests['Artist 1']!.complete(const []);
      await Future<void>.delayed(Duration.zero);
      expect(requests.length, 5);

      for (final entry in requests.entries) {
        if (!entry.value.isCompleted) entry.value.complete(const []);
      }
      await Future.wait(futures);
      expect(maxActiveRequests, 3);
    });

    test(
      'los resultados vacíos expiran pronto para permitir reintentos',
      () async {
        var now = DateTime.utc(2026);
        service = MusicCatalogService(spotify, lastFm, now: () => now);
        when(
          () => lastFm.getSimilarArtists('Unknown'),
        ).thenAnswer((_) async => const []);

        await service.getRelatedArtists('Unknown');
        await service.getRelatedArtists('Unknown');
        verify(() => lastFm.getSimilarArtists('Unknown')).called(1);

        now = now.add(const Duration(minutes: 5));
        await service.getRelatedArtists('Unknown');
        verify(() => lastFm.getSimilarArtists('Unknown')).called(1);
      },
    );
  });
}
