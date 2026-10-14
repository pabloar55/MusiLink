import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:musi_link/firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/session_provider.dart';
import 'package:musi_link/providers/theme_provider.dart';
import 'package:musi_link/providers/user_setup_provider.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/screens/mandatory_update_screen.dart';
import 'package:musi_link/screens/pwa_install_screen.dart';
import 'package:musi_link/services/app_update_service.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/app_localizations_delegates.dart';
import 'package:musi_link/utils/notification_navigation.dart';
import 'package:musi_link/utils/pwa_environment.dart';
import 'package:musi_link/utils/pwa_install_session.dart';
import 'package:musi_link/widgets/theme_environment_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether this web build is running with the Dart-to-Wasm compiler.
const isRunningWithWasm = bool.fromEnvironment('dart.tool.dart2wasm');

const _webRecaptchaEnterpriseSiteKey =
    '6LcYM5wtAAAAADlPteZ4HZwb6ib1WLNjSIqDnFYx';
const _forceAppCheckDebugProvider = bool.fromEnvironment(
  'USE_APP_CHECK_DEBUG_PROVIDER',
);

Future<void> _activateAppCheck() {
  final useDebugProvider =
      kDebugMode ||
      _forceAppCheckDebugProvider ||
      (kIsWeb &&
          (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1'));
  return FirebaseAppCheck.instance.activate(
    providerWeb: useDebugProvider
        ? WebDebugProvider()
        : ReCaptchaEnterpriseProvider(_webRecaptchaEnterpriseSiteKey),
    providerAndroid: useDebugProvider
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );
}

/// Enables the runtime compiler badge for manual web testing.
///
/// Pass `--dart-define=SHOW_RUNTIME_COMPILATION_BADGE=true` when running or
/// building. Keeping it opt-in prevents this diagnostic UI from appearing in
/// regular production builds.
const _showRuntimeCompilationBadge = bool.fromEnvironment(
  'SHOW_RUNTIME_COMPILATION_BADGE',
);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.data['type'] == 'new_message') {
    await NotificationService.showBackgroundChatNotification(message.data);
    // Firestore mantiene su caché en disco entre isolates y reinicios nativos.
    // Mostrar la notificación primero; no retrasarla por una consulta de red.
    try {
      await _activateAppCheck().timeout(const Duration(seconds: 3));
      await ChatService(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
        functions: FirebaseFunctions.instanceFor(
          region: firebaseFunctionsRegion,
        ),
      ).prepareNotificationChat(message.data);
    } catch (_) {
      // El sistema puede limitar el trabajo en segundo plano.
    }
  }
  if (kDebugMode) debugPrint('FCM background: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  if (!kIsWeb && kDebugMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }

  if (!kIsWeb) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  final prefs = await SharedPreferences.getInstance();
  final initialMessageFuture = FirebaseMessaging.instance.getInitialMessage();
  final localLaunchFuture = NotificationService.getLocalLaunchData();

  // Los valores de arranque se resuelven con servicios de este mismo
  // contenedor. Se asignan antes de runApp, que es cuando se leen por primera
  // vez al crear el router y las notificaciones.
  late final UserSetupBootstrapState userSetupBootstrapState;
  late final bool localLaunchHandled;
  late final String? initialLocation;
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localNotificationLaunchHandledProvider.overrideWith(
        (_) => localLaunchHandled,
      ),
      userSetupBootstrapStateProvider.overrideWith(
        (_) => userSetupBootstrapState,
      ),
      // Las pantallas previas al router (instalación de la PWA, actualización
      // obligatoria) dejan la URL en `/`, así que el router no puede leer de
      // ella la ruta inicial al crearse después.
      initialRouterLocationProvider.overrideWith((_) => initialLocation ?? '/'),
    ],
  );

  userSetupBootstrapState = await container
      .read(userSetupRepositoryProvider)
      .loadBootstrapState(
        container.read(firebaseAuthProvider).currentUser?.uid,
      );
  final initialMessage = await initialMessageFuture;
  final localLaunch = await localLaunchFuture;
  localLaunchHandled = localLaunch != null;
  final launchData = localLaunch ?? initialMessage?.data;
  final notificationLocation = launchData == null
      ? null
      : notificationLocationFromData(launchData);
  // En web el hash contiene la ruta con la que arranca la app: la de una
  // notificación o la de un enlace compartido.
  initialLocation = launchLocation(
    notificationLocation: notificationLocation,
    webFragment: kIsWeb ? Uri.base.fragment : null,
  );
  final chatId = directChatIdOf(initialLocation);
  if (chatId != null) {
    final chatService = container.read(chatServiceProvider);
    final cached = chatService.getCachedHistory(chatId);
    // Solo lectura local: nunca trasladar una espera de red al splash.
    final restore = chatService.restoreLocalHistory(chatId);
    if (cached == null) {
      await restore.timeout(
        const Duration(milliseconds: 150),
        onTimeout: () {},
      );
    } else {
      unawaited(restore);
    }
    if (launchData != null) {
      unawaited(chatService.prepareNotificationChat(launchData));
    }
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AppBootstrap(),
    ),
  );
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    this.updateChecker,
    this.immediateUpdateLauncher,
    this.mainAppBuilder,
    this.showPwaInstallOverride,
  });

  final AppUpdateChecker? updateChecker;
  final ImmediateUpdateLauncher? immediateUpdateLauncher;
  final Widget Function()? mainAppBuilder;
  final bool? showPwaInstallOverride;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  late final AppUpdateChecker _updateChecker;
  late final ImmediateUpdateLauncher _immediateUpdateLauncher;
  StreamSubscription<AppUpdatePolicy>? _policySubscription;
  AppUpdatePolicy? _policy;
  bool _openingStore = false;
  bool _immediateUpdateInProgress = false;
  bool _immediateUpdateAttempted = false;
  bool _storeOpenFailed = false;
  late bool _showPwaInstall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateChecker = widget.updateChecker ?? FirebaseAppUpdateService();
    _immediateUpdateLauncher =
        widget.immediateUpdateLauncher ?? const PlayImmediateUpdateLauncher();
    _showPwaInstall =
        widget.showPwaInstallOverride ??
        (kIsWeb &&
            isIosWebPlatform &&
            !isRunningAsInstalledPwa &&
            !hasDismissedPwaInstallForSession);
    _policySubscription = _updateChecker.policyUpdates.listen(
      _applyPolicy,
      onError: (_) {},
    );
    unawaited(_checkForUpdate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _policy?.isUpdateRequired == true) {
      unawaited(_checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    if (mounted) {
      setState(() {
        _storeOpenFailed = false;
      });
    }
    try {
      _applyPolicy(await _updateChecker.check());
    } catch (_) {
      // Fail-open: una incidencia temporal de Remote Config no debe bloquear
      // una versión válida. Las reglas de Firestore siguen siendo la barrera.
    }
  }

  void _applyPolicy(AppUpdatePolicy policy) {
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _storeOpenFailed = false;
    });
    if (policy.isUpdateRequired) {
      unawaited(_startImmediateUpdate());
    }
  }

  Future<ImmediateUpdateResult?> _startImmediateUpdate({
    bool force = false,
  }) async {
    final policy = _policy;
    if (policy?.platform != AppUpdatePlatform.android ||
        _immediateUpdateInProgress ||
        (_immediateUpdateAttempted && !force)) {
      return null;
    }

    setState(() {
      _immediateUpdateAttempted = true;
      _immediateUpdateInProgress = true;
      _storeOpenFailed = false;
    });
    final result = await _immediateUpdateLauncher.startImmediateUpdate();
    if (mounted) setState(() => _immediateUpdateInProgress = false);
    return result;
  }

  Future<void> _requestUpdate() async {
    if (_policy?.platform == AppUpdatePlatform.android) {
      final result = await _startImmediateUpdate(force: true);
      if (result == ImmediateUpdateResult.failed ||
          result == ImmediateUpdateResult.unavailable ||
          result == ImmediateUpdateResult.unsupported) {
        await _openStore();
      }
      return;
    }
    await _openStore();
  }

  Future<void> _retryUpdateCheck() async {
    _immediateUpdateAttempted = false;
    await _checkForUpdate();
  }

  Future<void> _openStore() async {
    final policy = _policy;
    if (policy == null) return;
    setState(() {
      _openingStore = true;
      _storeOpenFailed = false;
    });
    try {
      final opened = await launchUrl(
        policy.storeUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) setState(() => _storeOpenFailed = true);
    } catch (_) {
      if (mounted) setState(() => _storeOpenFailed = true);
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
  }

  void _continueInBrowser() {
    dismissPwaInstallForSession();
    setState(() => _showPwaInstall = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_policySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    if (policy?.isUpdateRequired == true) {
      return _BootstrapMaterialApp(
        home: MandatoryUpdateScreen(
          policy: policy!,
          onUpdate: _requestUpdate,
          onRetry: _retryUpdateCheck,
          isOpeningStore: _openingStore || _immediateUpdateInProgress,
          storeOpenFailed: _storeOpenFailed,
        ),
      );
    }
    if (_showPwaInstall) {
      return _BootstrapMaterialApp(
        home: PwaInstallScreen(onContinueInBrowser: _continueInBrowser),
      );
    }
    return widget.mainAppBuilder?.call() ?? const MainApp();
  }
}

class _BootstrapMaterialApp extends StatelessWidget {
  const _BootstrapMaterialApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => _RuntimeCompilationBadge(
        child: ThemeEnvironmentSync(child: child ?? const SizedBox.shrink()),
      ),
      home: home,
    );
  }
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  StreamSubscription<RemoteMessage>? _openedNotifications;
  int _notificationNavigationGeneration = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(pendingNotificationProvider, (_, data) {
      if (data == null) return;
      ref.read(pendingNotificationProvider.notifier).setValue(null);
      final location = notificationLocationFromData(data);
      if (location == null) return;
      final generation = ++_notificationNavigationGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _notificationNavigationGeneration) return;
        final router = ref.read(goRouterProvider);
        switch (notificationNavigation(
          current: router.state.uri,
          target: Uri.parse(location),
        )) {
          case NotificationNavigation.stay:
            break;
          case NotificationNavigation.push:
            unawaited(router.push(location));
          case NotificationNavigation.go:
            router.go(location);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }, fireImmediately: true);
    _openedNotifications = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      if (!mounted) return;
      unawaited(
        ref.read(chatServiceProvider).prepareNotificationChat(message.data),
      );
      ref.read(pendingNotificationProvider.notifier).setValue(message.data);
    });
    ref.listenManual(authStateProvider, (previous, next) {
      final previousUid = previous?.asData?.value?.uid;
      if (next.asData != null &&
          previousUid != null &&
          previousUid != next.asData?.value?.uid) {
        ref.read(sessionControllerProvider).discardUserState();
      }
      if (next.asData?.value != null) {
        ref.read(notificationServiceProvider).initialize().ignore();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _openedNotifications?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeInOut,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => _RuntimeCompilationBadge(
        child: ThemeEnvironmentSync(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _RuntimeCompilationBadge extends StatelessWidget {
  const _RuntimeCompilationBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_showRuntimeCompilationBadge) return child;

    return Banner(
      message: isRunningWithWasm ? 'WASM' : 'JS',
      location: BannerLocation.topEnd,
      color: isRunningWithWasm
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
      child: child,
    );
  }
}
