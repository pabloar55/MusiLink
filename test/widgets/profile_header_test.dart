import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/profile/profile_header.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

Widget _app({
  required ScrollController controller,
  required AppUser user,
  double textScale = 1,
  VoidCallback? onBack,
  VoidCallback? onMenu,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(320, 640),
        padding: const EdgeInsets.only(top: 24),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(
        builder: (context) => Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: ProfileHeader.expandedHeight(context, user),
                flexibleSpace: ProfileHeader(user: user),
                leading: BackButton(onPressed: onBack),
                actions: [
                  IconButton(
                    tooltip: 'Menu',
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1000)),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'la foto sigue el scroll y recupera la cabecera al volver arriba',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const user = AppUser(uid: 'alice', displayName: 'Alice');
      var backTaps = 0;
      var menuTaps = 0;
      await tester.pumpWidget(
        _app(
          controller: controller,
          user: user,
          onBack: () => backTaps++,
          onMenu: () => menuTaps++,
        ),
      );

      final photo = find.byType(UserProfilePhoto);
      final name = find.text(user.displayName);
      final expandedPhoto = tester.getRect(photo);
      expect(expandedPhoto.center.dx, 160);
      expect(tester.widget<Text>(name).textAlign, TextAlign.center);

      controller.jumpTo(1);
      await tester.pump();
      // The lower name is removed on the first scroll frame, without a fade.
      expect(name, findsOneWidget);
      expect(tester.widget<Text>(name).maxLines, 1);
      final fadingName = find.ancestor(
        of: name,
        matching: find.byType(Opacity),
      );
      expect(
        tester.widget<Opacity>(fadingName).opacity,
        inExclusiveRange(0, 1),
      );

      controller.jumpTo(100);
      await tester.pump();
      final intermediatePhoto = tester.getRect(photo);
      expect(intermediatePhoto.width, lessThan(expandedPhoto.width));
      expect(intermediatePhoto.left, lessThan(expandedPhoto.left));
      expect(intermediatePhoto.top, lessThan(expandedPhoto.top));
      expect(tester.getRect(name).left, greaterThan(intermediatePhoto.right));

      controller.jumpTo(400);
      await tester.pump();
      final compactPhoto = tester.getRect(photo);
      final back = tester.getRect(find.byType(BackButton));
      final menu = tester.getRect(find.byTooltip('Menu'));
      expect(compactPhoto.width, lessThan(intermediatePhoto.width));
      expect(compactPhoto.left, greaterThanOrEqualTo(back.right));
      expect(compactPhoto.center.dy, closeTo(back.center.dy, 0.01));
      expect(tester.getRect(name).left, greaterThan(compactPhoto.right));
      expect(tester.getRect(name).right, lessThanOrEqualTo(menu.left));
      expect(tester.widget<Opacity>(fadingName).opacity, 1);
      await tester.tap(find.byType(BackButton));
      await tester.tap(find.byTooltip('Menu'));
      expect(backTaps, 1);
      expect(menuTaps, 1);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getRect(photo), expandedPhoto);
      expect(name, findsOneWidget);
      expect(tester.widget<Text>(name).textAlign, TextAlign.center);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admite nombres largos y texto ampliado durante el scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const user = AppUser(
      uid: 'long-name',
      displayName: 'Un nombre de usuario muy largo para una pantalla pequeña',
    );
    await tester.pumpWidget(
      _app(controller: controller, user: user, textScale: 2),
    );
    final header = tester.getRect(find.byType(ProfileHeader));
    expect(
      tester.getRect(find.text(user.displayName)).bottom,
      lessThan(header.bottom),
    );
    for (final offset in [1.0, 80.0, 200.0, 400.0, 0.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      expect(find.byType(UserProfilePhoto), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
