import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'muestra los pasos de instalación y permite continuar en Safari',
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
}
