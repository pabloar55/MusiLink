import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/widgets/theme_environment_sync.dart';

void main() {
  testWidgets('actualiza la barra de sistema al cambiar de tema', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const darkBarColor = Color(0xFF121212);
      const lightBarColor = Colors.white;

      Future<void> pumpWithTheme(Brightness brightness, Color barColor) {
        return tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: barColor,
              ),
            ),
            builder: (context, child) =>
                ThemeEnvironmentSync(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        );
      }

      SystemUiOverlayStyle overlayStyle() {
        final annotatedRegion = tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            );
        return annotatedRegion.value;
      }

      await pumpWithTheme(Brightness.dark, darkBarColor);
      await tester.pumpAndSettle();
      expect(overlayStyle().systemNavigationBarColor, darkBarColor);
      expect(
        overlayStyle().systemNavigationBarIconBrightness,
        Brightness.light,
      );

      await pumpWithTheme(Brightness.light, lightBarColor);
      await tester.pumpAndSettle();
      expect(overlayStyle().systemNavigationBarColor, lightBarColor);
      expect(overlayStyle().systemNavigationBarIconBrightness, Brightness.dark);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
