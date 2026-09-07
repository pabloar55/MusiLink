import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/widgets/artist_avatar.dart';

void main() {
  testWidgets('muestra placeholder sin una URL de Spotify válida', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtistAvatar(imageUrl: 'https://example.com/artist.jpg'),
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.user), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('en web carga la imagen dentro del canvas de Flutter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ArtistAvatar(imageUrl: 'https://i.scdn.co/image/test'),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.never);
  }, skip: !kIsWeb);
}
