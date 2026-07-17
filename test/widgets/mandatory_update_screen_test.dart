import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/main.dart';
import 'package:musi_link/screens/mandatory_update_screen.dart';
import 'package:musi_link/services/app_update_service.dart';

class _FakeUpdateChecker implements AppUpdateChecker {
  _FakeUpdateChecker(this.policy);

  final AppUpdatePolicy policy;

  @override
  Future<AppUpdatePolicy> check({bool fetchRemote = true}) async => policy;

  @override
  Stream<AppUpdatePolicy> get policyUpdates => const Stream.empty();
}

class _FakeImmediateUpdateLauncher implements ImmediateUpdateLauncher {
  int calls = 0;

  @override
  Future<ImmediateUpdateResult> startImmediateUpdate() async {
    calls++;
    return ImmediateUpdateResult.cancelled;
  }
}

void main() {
  final policy = AppUpdatePolicy(
    platform: AppUpdatePlatform.android,
    currentBuild: 9,
    currentVersion: '1.0.5',
    minimumBuild: 10,
    forceUpdateEnabled: true,
    storeUri: Uri.parse('https://play.google.com/store/apps/details'),
  );

  testWidgets('bloquea la navegación y permite iniciar la actualización', (
    tester,
  ) async {
    var updateCalls = 0;
    var retryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MandatoryUpdateScreen(
          policy: policy,
          onUpdate: () async => updateCalls++,
          onRetry: () async => retryCalls++,
        ),
      ),
    );

    expect(find.text('Actualización obligatoria'), findsOneWidget);
    expect(find.text('Versión instalada: 1.0.5 (9)'), findsOneWidget);

    await tester.tap(find.text('Actualizar ahora'));
    await tester.tap(find.text('Comprobar de nuevo'));

    expect(updateCalls, 1);
    expect(retryCalls, 1);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
  });

  testWidgets('una política Android bloqueante inicia el flujo nativo', (
    tester,
  ) async {
    final launcher = _FakeImmediateUpdateLauncher();

    await tester.pumpWidget(
      AppBootstrap(
        updateChecker: _FakeUpdateChecker(policy),
        immediateUpdateLauncher: launcher,
      ),
    );
    await tester.pumpAndSettle();

    expect(launcher.calls, 1);
    expect(find.byType(MandatoryUpdateScreen), findsOneWidget);
    expect(find.text('Update required'), findsOneWidget);
  });
}
