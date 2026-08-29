import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

void main() {
  testWidgets('muestra el fallback cuando no hay URL', (tester) async {
    const fallbackKey = Key('fallback');

    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfilePhoto(
          photoUrl: '  ',
          fallback: SizedBox(key: fallbackKey),
        ),
      ),
    );

    expect(find.byKey(fallbackKey), findsOneWidget);
  });

  testWidgets('en web mantiene la foto en el canvas de Flutter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfilePhoto(
          photoUrl:
              'https://firebasestorage.googleapis.com/v0/b/'
              'musi-link-e7759.firebasestorage.app/o/'
              'profile_photos%2Falice?alt=media&token=test-token',
          fallback: SizedBox(),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.never);
  }, skip: !kIsWeb);

  testWidgets('no carga fotos externas no confiables', (tester) async {
    const fallbackKey = Key('untrusted-fallback');

    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfilePhoto(
          photoUrl: 'https://tracking.example/avatar.jpg',
          fallback: SizedBox(key: fallbackKey),
        ),
      ),
    );

    expect(find.byKey(fallbackKey), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
