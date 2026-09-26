import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/main.dart';
import 'package:musi_link/screens/pwa_install_screen.dart';
import 'package:musi_link/services/app_update_service.dart';

class _PendingUpdateChecker implements AppUpdateChecker {
  final Completer<AppUpdatePolicy> completer = Completer<AppUpdatePolicy>();

  @override
  Future<AppUpdatePolicy> check({bool fetchRemote = true}) => completer.future;

  @override
  Stream<AppUpdatePolicy> get policyUpdates => const Stream.empty();
}

void main() {
  testWidgets(
    'mantiene los pasos anteriores hasta Safari 26 y permite continuar',
    (tester) async {
      await tester.pumpWidget(
        AppBootstrap(
          updateChecker: _PendingUpdateChecker(),
          showPwaInstallOverride: true,
          mainAppBuilder: () =>
              const MaterialApp(home: Text('Aplicación principal')),
        ),
      );

      expect(find.byType(PwaInstallScreen), findsOneWidget);
      expect(find.text('Install MusiLink on your iPhone'), findsOneWidget);
      expect(
        find.text('Tap More (···) in the bottom-right corner.'),
        findsOneWidget,
      );
      expect(find.text('Choose “Add to Home Screen”.'), findsOneWidget);

      await tester.ensureVisible(find.text('Continue in Safari'));
      await tester.tap(find.text('Continue in Safari'));
      await tester.pump();

      expect(find.byType(PwaInstallScreen), findsNothing);
      expect(find.text('Aplicación principal'), findsOneWidget);
    },
  );

  testWidgets('muestra el nuevo botón de menú desde Safari 27', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PwaInstallScreen(onContinueInBrowser: () {}, useIos27Menu: true),
      ),
    );

    expect(
      find.text('Tap the Menu button (three lines) in the bottom-left corner.'),
      findsOneWidget,
    );
    expect(
      find.text('Tap More (···) in the bottom-right corner.'),
      findsNothing,
    );
  });
}
