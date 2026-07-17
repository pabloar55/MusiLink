import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:musi_link/firebase_options.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/theme_provider.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/screens/mandatory_update_screen.dart';
import 'package:musi_link/screens/onboarding_screen.dart';
import 'package:musi_link/screens/photo_setup_screen.dart';
import 'package:musi_link/services/app_update_service.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/notification_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.data['type'] == 'new_message') {
    await NotificationService.showBackgroundChatNotification(message.data);
  }
  if (kDebugMode) debugPrint('FCM background: ${message.messageId}');
}

Future<AppRouterBootstrapState> _loadRouterBootstrapState(
  SharedPreferences prefs,
) async {
  final authUser = FirebaseAuth.instance.currentUser;
  final uid = authUser?.uid;
  bool usernameSet = false;
  bool artistsSelected = false;

  if (uid != null) {
    try {
      await authUser?.getIdToken();
      final user = await UserService(
        firestore: FirebaseFirestore.instance,
      ).getUser(uid, reportErrors: false);
      usernameSet = user != null && user.username.isNotEmpty;
      artistsSelected = user != null && user.topArtistNames.isNotEmpty;
    } catch (_) {}
  }

  final onboardingDone =
      artistsSelected ||
      (prefs.getBool(OnboardingScreen.onboardingCompletedKey) ?? false);
  final photoSetupDone =
      onboardingDone ||
      (prefs.getBool(PhotoSetupScreen.photoSetupDoneKey) ?? false);

  if (onboardingDone &&
      !(prefs.getBool(PhotoSetupScreen.photoSetupDoneKey) ?? false)) {
    await prefs.setBool(PhotoSetupScreen.photoSetupDoneKey, true);
  }

  return AppRouterBootstrapState(
    usernameSet: usernameSet,
    artistsSelected: artistsSelected,
    onboardingDone: onboardingDone,
    photoSetupDone: photoSetupDone,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
  final routerBootstrapState = await _loadRouterBootstrapState(prefs);
  final initialMessage = await initialMessageFuture;
  final notificationLocation = initialMessage == null
      ? null
      : notificationLocationFromData(initialMessage.data);
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  unawaited(FirebaseAnalytics.instance.logEvent(name: 'app_open'));

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routerBootstrapStateProvider.overrideWithValue(routerBootstrapState),
        initialRouterLocationProvider.overrideWithValue(
          notificationLocation ?? '/',
        ),
      ],
      child: const AppBootstrap(),
    ),
  );
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    this.updateChecker,
    this.immediateUpdateLauncher,
  });

  final AppUpdateChecker? updateChecker;
  final ImmediateUpdateLauncher? immediateUpdateLauncher;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  late final AppUpdateChecker _updateChecker;
  late final ImmediateUpdateLauncher _immediateUpdateLauncher;
  StreamSubscription<AppUpdatePolicy>? _policySubscription;
  AppUpdatePolicy? _policy;
  bool _checking = true;
  bool _openingStore = false;
  bool _immediateUpdateInProgress = false;
  bool _immediateUpdateAttempted = false;
  bool _storeOpenFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateChecker = widget.updateChecker ?? FirebaseAppUpdateService();
    _immediateUpdateLauncher =
        widget.immediateUpdateLauncher ?? const PlayImmediateUpdateLauncher();
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
        _checking = true;
        _storeOpenFailed = false;
      });
    }
    try {
      _applyPolicy(await _updateChecker.check());
    } catch (_) {
      // Fail-open: una incidencia temporal de Remote Config no debe bloquear
      // una versión válida. Las reglas de Firestore siguen siendo la barrera.
      if (mounted) setState(() => _checking = false);
    }
  }

  void _applyPolicy(AppUpdatePolicy policy) {
    if (!mounted) return;
    setState(() {
      _policy = policy;
      _checking = false;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_policySubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    if (_checking && policy == null) {
      return const _BootstrapMaterialApp(home: _UpdateCheckLoadingScreen());
    }
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
    return const MainApp();
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }
}

class _UpdateCheckLoadingScreen extends StatelessWidget {
  const _UpdateCheckLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      themeAnimationDuration: const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeInOut,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
