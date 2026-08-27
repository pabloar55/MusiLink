import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/screens/artist_selector_screen.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/widgets/chat/track_search_sheet.dart';
import 'package:musi_link/widgets/discover/daily_song_search_sheet.dart';

class _MockMusicCatalogService extends Mock implements MusicCatalogService {}

Widget _app({
  required MusicCatalogService musicCatalogService,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      musicCatalogServiceProvider.overrideWithValue(musicCatalogService),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

const _oldTrack = Track(title: 'Old track', artist: 'Old artist', imageUrl: '');
const _newTrack = Track(title: 'New track', artist: 'New artist', imageUrl: '');
const _oldArtist = Artist(name: 'Old artist result', imageUrl: '', genres: []);
const _newArtist = Artist(name: 'New artist result', imageUrl: '', genres: []);

void main() {
  late _MockMusicCatalogService musicCatalogService;

  setUp(() {
    musicCatalogService = _MockMusicCatalogService();
  });

  testWidgets('el buscador del chat ignora respuestas antiguas', (
    tester,
  ) async {
    final oldResult = Completer<List<Track>>();
    final newResult = Completer<List<Track>>();
    when(() => musicCatalogService.searchTracks('old'))
        .thenAnswer((_) => oldResult.future);
    when(() => musicCatalogService.searchTracks('new'))
        .thenAnswer((_) => newResult.future);

    await tester.pumpWidget(
      _app(
        musicCatalogService: musicCatalogService,
        child: TrackSearchSheet(onTrackSelected: (_) {}),
      ),
    );
    final searchField = find.byType(TextField);

    await tester.enterText(searchField, 'old');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(searchField, 'new');
    await tester.pump(const Duration(milliseconds: 500));

    newResult.complete(const [_newTrack]);
    await tester.pump();
    expect(find.text(_newTrack.title), findsOneWidget);

    oldResult.complete(const [_oldTrack]);
    await tester.pump();
    expect(find.text(_newTrack.title), findsOneWidget);
    expect(find.text(_oldTrack.title), findsNothing);
  });

  testWidgets('el buscador de canción del día ignora respuestas antiguas', (
    tester,
  ) async {
    final oldResult = Completer<List<Track>>();
    final newResult = Completer<List<Track>>();
    when(() => musicCatalogService.searchTracks('old'))
        .thenAnswer((_) => oldResult.future);
    when(() => musicCatalogService.searchTracks('new'))
        .thenAnswer((_) => newResult.future);

    await tester.pumpWidget(
      _app(
        musicCatalogService: musicCatalogService,
        child: const DailySongSearchSheet(),
      ),
    );
    final searchField = find.byType(TextField);

    await tester.enterText(searchField, 'old');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(searchField, 'new');
    await tester.pump(const Duration(milliseconds: 500));

    newResult.complete(const [_newTrack]);
    await tester.pump();
    expect(find.text(_newTrack.title), findsOneWidget);

    oldResult.complete(const [_oldTrack]);
    await tester.pump();
    expect(find.text(_newTrack.title), findsOneWidget);
    expect(find.text(_oldTrack.title), findsNothing);
  });

  testWidgets('el buscador de artistas ignora respuestas antiguas', (
    tester,
  ) async {
    final oldResult = Completer<List<Artist>>();
    final newResult = Completer<List<Artist>>();
    when(() => musicCatalogService.searchArtists('old', limit: 10))
        .thenAnswer((_) => oldResult.future);
    when(() => musicCatalogService.searchArtists('new', limit: 10))
        .thenAnswer((_) => newResult.future);

    await tester.pumpWidget(
      _app(
        musicCatalogService: musicCatalogService,
        child: const ArtistSelectorScreen(),
      ),
    );
    final searchField = find.byType(TextField);

    await tester.enterText(searchField, 'old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(searchField, 'new');
    await tester.pump(const Duration(milliseconds: 400));

    newResult.complete(const [_newArtist]);
    await tester.pump();
    expect(find.text(_newArtist.name), findsOneWidget);

    oldResult.complete(const [_oldArtist]);
    await tester.pump();
    expect(find.text(_newArtist.name), findsOneWidget);
    expect(find.text(_oldArtist.name), findsNothing);
  });

  testWidgets('vaciar artistas invalida la petición y detiene la carga', (
    tester,
  ) async {
    final oldResult = Completer<List<Artist>>();
    when(() => musicCatalogService.searchArtists('old', limit: 10))
        .thenAnswer((_) => oldResult.future);

    await tester.pumpWidget(
      _app(
        musicCatalogService: musicCatalogService,
        child: const ArtistSelectorScreen(),
      ),
    );
    final searchField = find.byType(TextField);

    await tester.enterText(searchField, 'old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(searchField, '');
    await tester.pump();

    expect(
      find.text('Search for your favourite artists to get started'),
      findsOneWidget,
    );

    oldResult.complete(const [_oldArtist]);
    await tester.pump();
    expect(find.text(_oldArtist.name), findsNothing);
    expect(
      find.text('Search for your favourite artists to get started'),
      findsOneWidget,
    );
  });

  testWidgets('las sugerencias solo consultan el artista recién añadido', (
    tester,
  ) async {
    const firstArtist = Artist(
      name: 'First selected artist',
      imageUrl: '',
      genres: [],
    );
    const secondArtist = Artist(
      name: 'Second selected artist',
      imageUrl: '',
      genres: [],
    );
    final relatedCalls = <String>[];

    when(() => musicCatalogService.searchArtists('first', limit: 10))
        .thenAnswer((_) async => const [firstArtist]);
    when(() => musicCatalogService.searchArtists('second', limit: 10))
        .thenAnswer((_) async => const [secondArtist]);
    when(() => musicCatalogService.searchArtists(firstArtist.name, limit: 1))
        .thenAnswer((_) async => const [firstArtist]);
    when(() => musicCatalogService.searchArtists(secondArtist.name, limit: 1))
        .thenAnswer((_) async => const [secondArtist]);
    when(() => musicCatalogService.getRelatedArtists(any())).thenAnswer((call) {
      relatedCalls.add(call.positionalArguments.first as String);
      return Future.value(const []);
    });

    await tester.pumpWidget(
      _app(
        musicCatalogService: musicCatalogService,
        child: const ArtistSelectorScreen(),
      ),
    );
    final searchField = find.byType(TextField);

    await tester.enterText(searchField, 'first');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text(firstArtist.name));
    await tester.pump();

    await tester.enterText(searchField, 'second');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text(secondArtist.name));
    await tester.pump();

    expect(relatedCalls, [firstArtist.name, secondArtist.name]);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(relatedCalls, [firstArtist.name, secondArtist.name]);
  });
}
