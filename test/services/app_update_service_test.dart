import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/services/app_update_service.dart';

void main() {
  AppUpdatePolicy policy({
    AppUpdatePlatform platform = AppUpdatePlatform.android,
    int currentBuild = 9,
    int minimumBuild = 10,
    bool enabled = true,
    String storeUrl = 'https://example.com/store',
  }) {
    return AppUpdatePolicy.evaluate(
      platform: platform,
      currentBuild: currentBuild,
      currentVersion: '1.0.5',
      minimumBuild: minimumBuild,
      forceUpdateEnabled: enabled,
      configuredStoreUrl: storeUrl,
    );
  }

  group('AppUpdatePolicy', () {
    test('bloquea una build inferior al mínimo cuando está activado', () {
      expect(policy().isUpdateRequired, isTrue);
    });

    test('admite una build igual o superior al mínimo', () {
      expect(policy(currentBuild: 10).isUpdateRequired, isFalse);
      expect(policy(currentBuild: 11).isUpdateRequired, isFalse);
    });

    test('el interruptor remoto desactiva el bloqueo', () {
      expect(policy(enabled: false).isUpdateRequired, isFalse);
    });

    test('no bloquea plataformas no compatibles ni builds desconocidas', () {
      expect(
        policy(platform: AppUpdatePlatform.unsupported).isUpdateRequired,
        isFalse,
      );
      expect(policy(currentBuild: 0).isUpdateRequired, isFalse);
    });

    test('normaliza mínimos negativos', () {
      final result = policy(minimumBuild: -1);

      expect(result.minimumBuild, 0);
      expect(result.isUpdateRequired, isFalse);
    });

    test('acepta únicamente URLs HTTPS válidas', () {
      expect(policy().storeUri, Uri.parse('https://example.com/store'));
      expect(
        policy(storeUrl: 'javascript:alert(1)').storeUri,
        Uri.parse(FirebaseAppUpdateService.defaultAndroidStoreUrl),
      );
    });
  });
}
