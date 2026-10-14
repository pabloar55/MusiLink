import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/artist_selector_controller.dart';
import 'package:musi_link/services/music_catalog_service.dart';

class _MockMusicCatalogService extends Mock implements MusicCatalogService {}

Artist _artist(String name) =>
    Artist(name: name, imageUrl: 'https://i.scdn.co/image/$name', genres: []);

List<String> _names(Iterable<Artist> artists) =>
    artists.map((artist) => artist.name).toList();

void main() {
  late _MockMusicCatalogService catalog;
  late ArtistSelectorController selection;

  setUp(() {
    catalog = _MockMusicCatalogService();
    when(() => catalog.getRelatedArtists(any())).thenAnswer((_) async => []);
    selection = ArtistSelectorController(catalog: catalog);
    addTearDown(selection.dispose);
  });

  // testWidgets aporta el reloj simulado para la espera entre pulsaciones.
  testWidgets(
    'una búsqueda anterior no sustituye los resultados de la última',
    (tester) async {
      final slowSearch = Completer<List<Artist>>();
      when(() => catalog.searchArtists('mu', limit: 10))
          .thenAnswer((_) => slowSearch.future);
      when(() => catalog.searchArtists('muse', limit: 10))
          .thenAnswer((_) async => [_artist('Muse')]);

      selection.searchController.text = 'mu';
      await tester.pump(const Duration(milliseconds: 400));
      selection.searchController.text = 'muse';
      expect(selection.isSearching, isTrue);
      await tester.pump(const Duration(milliseconds: 400));

      expect(_names(selection.searchResults), ['Muse']);
      expect(selection.isSearching, isFalse);

      slowSearch.complete([_artist('Mumford & Sons')]);
      await tester.pump();

      expect(_names(selection.searchResults), ['Muse']);
    },
  );

  testWidgets('los resultados omiten artistas elegidos y repetidos', (
    tester,
  ) async {
    await selection.restore([_artist('Muse')]);
    when(() => catalog.searchArtists('m', limit: 10)).thenAnswer(
      (_) async => [
        _artist('MUSE'),
        _artist('Massive Attack'),
        _artist('massive attack!'),
      ],
    );

    selection.searchController.text = 'm';
    await tester.pump(const Duration(milliseconds: 400));

    expect(_names(selection.searchResults), ['Massive Attack']);
  });

  test(
    'las sugerencias intercalan similares empezando por el último añadido',
    () async {
      final muse = _artist('Muse');
      final blur = _artist('Blur');
      when(() => catalog.getRelatedArtists('Muse')).thenAnswer(
        (_) async => [
          _artist('Radiohead'),
          _artist('Blur'),
          _artist('Placebo'),
        ],
      );
      when(() => catalog.getRelatedArtists('Blur')).thenAnswer(
        (_) async => [_artist('Oasis'), _artist('radiohead'), _artist('Pulp')],
      );

      await selection.restore([muse]);
      expect(_names(selection.suggestions), ['Radiohead', 'Blur', 'Placebo']);

      selection.toggle(blur);
      await pumpEventQueue();

      // Blur pasa delante por ser el último añadido y ya no se sugiere.
      expect(_names(selection.suggestions), [
        'Oasis',
        'Radiohead',
        'Pulp',
        'Placebo',
      ]);

      selection.toggle(blur);

      expect(_names(selection.suggestions), ['Radiohead', 'Blur', 'Placebo']);
      verify(() => catalog.getRelatedArtists('Blur')).called(1);
    },
  );

  test(
    'restaurar limita el perfil y solo busca similares de los primeros',
    () async {
      await selection.restore([
        for (var i = 0; i < ArtistSelectorController.maxArtists + 5; i++)
          _artist('Artist $i'),
      ]);

      expect(
        selection.selected,
        hasLength(ArtistSelectorController.maxArtists),
      );
      expect(selection.hasChanges, isFalse);
      verify(() => catalog.getRelatedArtists(any())).called(5);

      selection.toggle(_artist('Otro'));
      expect(
        selection.selected,
        hasLength(ArtistSelectorController.maxArtists),
      );
    },
  );

  test('los cambios se miden contra el ranking restaurado', () async {
    await selection.restore([
      _artist('Muse'),
      _artist('muse!'),
      _artist('Blur'),
    ]);
    expect(_names(selection.selected), ['Muse', 'Blur']);

    selection.reorder(0, 1);
    expect(_names(selection.selected), ['Blur', 'Muse']);
    expect(selection.hasChanges, isTrue);

    selection.reorder(0, 1);
    expect(selection.hasChanges, isFalse);

    selection.toggle(_artist('Blur'));
    expect(selection.hasChanges, isTrue);
  });
  test('el catálogo solo completa un artista con el mismo artista', () async {
    const vandi = Artist(name: 'Βανδή', imageUrl: '', genres: []);
    const nirvana = Artist(
      name: 'Nirvana',
      imageUrl: '',
      genres: [],
      spotifyId: 'us',
    );
    when(() => catalog.searchArtists('Βανδή', limit: 1))
        .thenAnswer((_) async => [_artist('Ρουβάς')]);
    when(() => catalog.searchArtists('Nirvana', limit: 1)).thenAnswer(
      (_) async => [
        const Artist(
          name: 'Nirvana',
          imageUrl: 'https://i.scdn.co/image/uk',
          genres: [],
          spotifyId: 'uk',
        ),
      ],
    );

    selection
      ..toggle(vandi)
      ..toggle(nirvana);
    await pumpEventQueue();

    expect(selection.selected, [vandi, nirvana]);
  });

  test('completar un artista no cuenta como cambio', () async {
    const blur = Artist(name: 'Blur', imageUrl: '', genres: []);
    const enrichedBlur = Artist(
      name: 'Blur',
      imageUrl: 'https://i.scdn.co/image/blur',
      genres: ['britpop'],
      spotifyId: 'blur',
    );
    when(() => catalog.searchArtists('Blur', limit: 1))
        .thenAnswer((_) async => [enrichedBlur]);
    await selection.restore([_artist('Muse'), blur]);

    selection
      ..toggle(blur)
      ..toggle(blur);
    await pumpEventQueue();

    expect(selection.selected.last, same(enrichedBlur));
    expect(selection.hasChanges, isFalse);
  });

  testWidgets(
    'los resultados distinguen homónimos y omiten lo que el backend rechaza',
    (tester) async {
      const nirvanaUs = Artist(
        name: 'Nirvana',
        imageUrl: 'https://i.scdn.co/image/us',
        genres: [],
        spotifyId: 'us',
      );
      const nirvanaUk = Artist(
        name: 'Nirvana',
        imageUrl: 'https://i.scdn.co/image/uk',
        genres: [],
        spotifyId: 'uk',
      );
      await selection.restore([
        nirvanaUs,
        _artist('Beyoncé'),
        _artist('Simon & Garfunkel'),
      ]);
      when(() => catalog.searchArtists('n', limit: 10)).thenAnswer(
        (_) async => [
          nirvanaUs,
          nirvanaUk,
          _artist('Beyonce'),
          _artist('Simon and Garfunkel'),
          _artist('Βανδή'),
          _artist('Ρουβάς'),
        ],
      );

      selection.searchController.text = 'n';
      await tester.pump(const Duration(milliseconds: 400));

      expect(selection.searchResults, [
        nirvanaUk,
        _artistNamed(selection.searchResults, 'Βανδή'),
        _artistNamed(selection.searchResults, 'Ρουβάς'),
      ]);
      expect(selection.isSelected(nirvanaUk), isFalse);
    },
  );
}

Artist _artistNamed(List<Artist> artists, String name) =>
    artists.firstWhere((artist) => artist.name == name);
