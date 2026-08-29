import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/widgets/track_tile.dart';

void main() {
  group('TrackTile', () {
    testWidgets('muestra título y artista', (tester) async {
      const track = Track(
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        imageUrl: '',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TrackTile(track: track)),
        ),
      );

      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('Queen'), findsOneWidget);
    });

    testWidgets('muestra icono cuando imageUrl está vacío', (tester) async {
      const track = Track(title: 'Test', artist: 'Artist', imageUrl: '');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TrackTile(track: track)),
        ),
      );

      expect(find.byIcon(LucideIcons.music), findsOneWidget);
    });

    testWidgets('muestra icono para una imagen externa no confiable', (
      tester,
    ) async {
      const track = Track(
        title: 'Test',
        artist: 'Artist',
        imageUrl: 'https://tracking.example/song.jpg',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TrackTile(track: track)),
        ),
      );

      expect(find.byIcon(LucideIcons.music), findsOneWidget);
    });
  });
}
