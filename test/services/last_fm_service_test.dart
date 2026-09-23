import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/last_fm_service.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/services/spotify_cloud_service.dart';

import '../helpers/mocks.dart';

class _MockSpotifyCloudService extends Mock implements SpotifyCloudService {}

void main() {
  late MockFirebaseFunctions functions;
  late MockHttpsCallable callable;
  late MockHttpsCallableResult<List<dynamic>> result;
  late LastFmService lastFm;
  late MusicCatalogService catalog;

  setUp(() {
    functions = MockFirebaseFunctions();
    callable = MockHttpsCallable();
    result = MockHttpsCallableResult<List<dynamic>>();
    when(() => functions.httpsCallable('getSimilarArtists'))
        .thenReturn(callable);
    when(() => result.data).thenReturn(['Radiohead']);
    when(() => callable.call<List<dynamic>>(any()))
        .thenAnswer((_) async => result);
    lastFm = LastFmService(functions);
    catalog = MusicCatalogService(_MockSpotifyCloudService(), lastFm);
  });

  for (final code in ['resource-exhausted', 'unavailable', 'internal']) {
    test('propaga $code y permite reintentar sin cachear el error', () async {
      final failure = MockFirebaseFunctionsException();
      when(() => failure.code).thenReturn(code);
      var attempts = 0;
      when(() => callable.call<List<dynamic>>(any())).thenAnswer((_) async {
        if (attempts++ == 0) throw failure;
        return result;
      });

      await expectLater(
        catalog.getRelatedArtists('Muse'),
        throwsA(same(failure)),
      );
      final recovered = await catalog.getRelatedArtists('Muse');
      expect(recovered.map((artist) => artist.name), ['Radiohead']);
      expect(await catalog.getRelatedArtists('muse'), same(recovered));
      verify(() => callable.call<List<dynamic>>(any())).called(2);
    });
  }

  test(
    'mantiene el contrato de limit y los resultados realmente vacíos',
    () async {
      when(() => result.data).thenReturn([]);
      expect(await lastFm.getSimilarArtists('Muse', limit: 1), isEmpty);
      verify(
        () => callable.call<List<dynamic>>({'artistName': 'Muse', 'limit': 1}),
      ).called(1);

      expect(await catalog.getRelatedArtists('Muse'), isEmpty);
      expect(await catalog.getRelatedArtists('Muse'), isEmpty);
      verify(
        () => callable.call<List<dynamic>>({'artistName': 'Muse', 'limit': 10}),
      ).called(1);
    },
  );
}
