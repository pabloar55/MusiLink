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

  testWidgets('en web reintenta la foto con un elemento HTML', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UserProfilePhoto(
          photoUrl: 'https://example.test/avatar.jpg',
          fallback: SizedBox(),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.fallback);
  }, skip: !kIsWeb);
}
