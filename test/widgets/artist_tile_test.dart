import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/widgets/artist_tile.dart';

void main() {
  group('ArtistTile', () {
    testWidgets('muestra nombre del artista', (tester) async {
      const artist = Artist(
        name: 'Radiohead',
        imageUrl: '',
        genres: ['alternative rock'],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ArtistTile(artist: artist)),
        ),
      );

      expect(find.text('Radiohead'), findsOneWidget);
    });

    testWidgets('muestra icono cuando imageUrl está vacío', (tester) async {
      const artist = Artist(name: 'Test Artist', imageUrl: '', genres: []);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ArtistTile(artist: artist)),
        ),
      );

      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('muestra icono para una imagen externa no confiable', (
      tester,
    ) async {
      const artist = Artist(
        name: 'Test Artist',
        imageUrl: 'https://tracking.example/artist.jpg',
        genres: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ArtistTile(artist: artist)),
        ),
      );

      expect(find.byIcon(LucideIcons.user), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('en web carga la imagen dentro del canvas de Flutter', (
      tester,
    ) async {
      const artist = Artist(
        name: 'Test Artist',
        imageUrl: 'https://i.scdn.co/image/test',
        genres: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ArtistTile(artist: artist)),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as NetworkImage;
      expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.never);
    }, skip: !kIsWeb);
  });
}
