import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum AppUpdatePlatform { android, ios, unsupported }

class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.platform,
    required this.currentBuild,
    required this.currentVersion,
    required this.minimumBuild,
    required this.forceUpdateEnabled,
    required this.storeUri,
  });

  final AppUpdatePlatform platform;
  final int currentBuild;
  final String currentVersion;
  final int minimumBuild;
  final bool forceUpdateEnabled;
  final Uri storeUri;

  bool get isUpdateRequired =>
      platform != AppUpdatePlatform.unsupported &&
      forceUpdateEnabled &&
      currentBuild > 0 &&
      minimumBuild > currentBuild;

  static AppUpdatePolicy evaluate({
    required AppUpdatePlatform platform,
    required int currentBuild,
    required String currentVersion,
    required int minimumBuild,
    required bool forceUpdateEnabled,
    required String configuredStoreUrl,
  }) {
    return AppUpdatePolicy(
      platform: platform,
      currentBuild: currentBuild,
      currentVersion: currentVersion,
      minimumBuild: minimumBuild < 0 ? 0 : minimumBuild,
      forceUpdateEnabled: forceUpdateEnabled,
      storeUri: _safeStoreUri(platform, configuredStoreUrl),
    );
  }

  static Uri _safeStoreUri(AppUpdatePlatform platform, String configuredUrl) {
    final parsed = Uri.tryParse(configuredUrl.trim());
    if (parsed != null && parsed.scheme == 'https' && parsed.host.isNotEmpty) {
      return parsed;
    }

    return switch (platform) {
      AppUpdatePlatform.android => Uri.parse(
        FirebaseAppUpdateService.defaultAndroidStoreUrl,
      ),
      AppUpdatePlatform.ios => Uri.parse(
        FirebaseAppUpdateService.defaultIosStoreUrl,
      ),
      AppUpdatePlatform.unsupported => Uri.parse('https://musilink.app'),
    };
  }
}

abstract interface class AppUpdateChecker {
  Future<AppUpdatePolicy> check({bool fetchRemote = true});

  Stream<AppUpdatePolicy> get policyUpdates;
}

enum ImmediateUpdateResult {
  completed,
  cancelled,
  unavailable,
  failed,
  inProgress,
  unsupported,
}

abstract interface class ImmediateUpdateLauncher {
  Future<ImmediateUpdateResult> startImmediateUpdate();
}

class PlayImmediateUpdateLauncher implements ImmediateUpdateLauncher {
  const PlayImmediateUpdateLauncher();

  static const _channel = MethodChannel('app.musilink/play_in_app_update');

  @override
  Future<ImmediateUpdateResult> startImmediateUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return ImmediateUpdateResult.unsupported;
    }

    try {
      final status = await _channel.invokeMethod<String>(
        'startImmediateUpdate',
      );
      return switch (status) {
        'completed' => ImmediateUpdateResult.completed,
        'cancelled' => ImmediateUpdateResult.cancelled,
        'unavailable' => ImmediateUpdateResult.unavailable,
        'inProgress' => ImmediateUpdateResult.inProgress,
        _ => ImmediateUpdateResult.failed,
      };
    } on PlatformException {
      return ImmediateUpdateResult.failed;
    } on MissingPluginException {
      return ImmediateUpdateResult.unsupported;
    }
  }
}

class FirebaseAppUpdateService implements AppUpdateChecker {
  FirebaseAppUpdateService({
    FirebaseRemoteConfig? remoteConfig,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _remoteConfig = remoteConfig ?? FirebaseRemoteConfig.instance,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  static const forceUpdateEnabledKey = 'force_update_enabled';
  static const minimumAndroidBuildKey = 'minimum_android_build';
  static const minimumIosBuildKey = 'minimum_ios_build';
  static const androidStoreUrlKey = 'android_store_url';
  static const iosStoreUrlKey = 'ios_store_url';

  static const defaultAndroidStoreUrl =
      'https://play.google.com/store/apps/details?id=app.musilink';
  static const defaultIosStoreUrl =
      'https://apps.apple.com/search?term=MusiLink';

  final FirebaseRemoteConfig _remoteConfig;
  final Future<PackageInfo> Function() _packageInfoLoader;

  Future<void>? _configurationFuture;

  Future<void> _ensureConfigured() {
    return _configurationFuture ??= _configure();
  }

  Future<void> _configure() async {
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 8),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await _remoteConfig.setDefaults(const {
      forceUpdateEnabledKey: false,
      minimumAndroidBuildKey: 0,
      minimumIosBuildKey: 0,
      androidStoreUrlKey: defaultAndroidStoreUrl,
      iosStoreUrlKey: defaultIosStoreUrl,
    });
  }

  @override
  Future<AppUpdatePolicy> check({bool fetchRemote = true}) async {
    await _ensureConfigured();
    if (fetchRemote) {
      try {
        await _remoteConfig.fetchAndActivate();
      } catch (_) {
        // Conserva la última configuración activada. En una primera ejecución
        // sin red se aplican los defaults (fail-open) para no bloquear por una
        // incidencia de Firebase; las reglas siguen protegiendo el backend.
      }
    }

    return _currentPolicy(await _packageInfoLoader());
  }

  @override
  Stream<AppUpdatePolicy> get policyUpdates async* {
    await _ensureConfigured();
    await for (final update in _remoteConfig.onConfigUpdated) {
      if (!update.updatedKeys.any(_isUpdatePolicyKey)) continue;
      await _remoteConfig.activate();
      yield _currentPolicy(await _packageInfoLoader());
    }
  }

  bool _isUpdatePolicyKey(String key) =>
      key == forceUpdateEnabledKey ||
      key == minimumAndroidBuildKey ||
      key == minimumIosBuildKey ||
      key == androidStoreUrlKey ||
      key == iosStoreUrlKey;

  AppUpdatePolicy _currentPolicy(PackageInfo packageInfo) {
    final platform = _currentPlatform();
    final minimumBuild = switch (platform) {
      AppUpdatePlatform.android => _remoteConfig.getInt(minimumAndroidBuildKey),
      AppUpdatePlatform.ios => _remoteConfig.getInt(minimumIosBuildKey),
      AppUpdatePlatform.unsupported => 0,
    };
    final storeUrl = switch (platform) {
      AppUpdatePlatform.android => _remoteConfig.getString(androidStoreUrlKey),
      AppUpdatePlatform.ios => _remoteConfig.getString(iosStoreUrlKey),
      AppUpdatePlatform.unsupported => '',
    };

    return AppUpdatePolicy.evaluate(
      platform: platform,
      currentBuild: int.tryParse(packageInfo.buildNumber) ?? 0,
      currentVersion: packageInfo.version,
      minimumBuild: minimumBuild,
      forceUpdateEnabled: _remoteConfig.getBool(forceUpdateEnabledKey),
      configuredStoreUrl: storeUrl,
    );
  }

  AppUpdatePlatform _currentPlatform() {
    if (kIsWeb) return AppUpdatePlatform.unsupported;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AppUpdatePlatform.android,
      TargetPlatform.iOS => AppUpdatePlatform.ios,
      _ => AppUpdatePlatform.unsupported,
    };
  }
}
