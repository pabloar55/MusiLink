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
import 'package:musi_link/screens/onboarding_screen.dart';
import 'package:musi_link/screens/photo_setup_screen.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/notification_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
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

  if (kDebugMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

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
      child: const MainApp(),
    ),
  );
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
