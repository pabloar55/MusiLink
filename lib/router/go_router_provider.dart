import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/router/app_route_observer.dart';
import 'package:musi_link/screens/account_settings_screen.dart';
import 'package:musi_link/screens/deleting_account_screen.dart';
import 'package:musi_link/screens/blocked_users_screen.dart';
import 'package:musi_link/screens/auth_screen.dart';
import 'package:musi_link/screens/privacy_policy_screen.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/screens/main_screen.dart';
import 'package:musi_link/screens/onboarding_screen.dart';
import 'package:musi_link/screens/photo_setup_screen.dart';
import 'package:musi_link/screens/artist_selector_screen.dart';
import 'package:musi_link/screens/username_setup_screen.dart';
import 'package:musi_link/screens/user_profile_route_screen.dart';
import 'package:musi_link/screens/user_search_screen.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:musi_link/utils/user_setup_cache.dart';

// ── Router ──────────────────────────────────────────────────────

final routerBootstrapStateProvider = Provider<AppRouterBootstrapState?>(
  (ref) => null,
);

final initialRouterLocationProvider = Provider<String>((ref) => '/');

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  final userService = ref.read(userServiceProvider);
  final prefs = ref.read(sharedPreferencesProvider);
  final notifier = AppRouterNotifier(
    auth: ref.watch(firebaseAuthProvider),
    initialState: ref.watch(routerBootstrapStateProvider),
    readCachedUserState: (loginUid) {
      final cached = UserSetupCache.read(prefs, loginUid);
      if (cached == null) return null;
      return (
        usernameSet: cached.usernameSet,
        artistsSelected: cached.artistsSelected,
        onboardingDone: cached.onboardingDone,
        photoSetupDone: cached.photoSetupDone,
        deletionPending: null,
      );
    },
    fetchUserState: (loginUid) async {
      final deletionPendingFuture = (() async {
        try {
          final deletionJob = await ref
              .read(firebaseFirestoreProvider)
              .collection(FirestoreCollections.accountDeletions)
              .doc(loginUid)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 5));
          return deletionJob.exists;
        } catch (_) {
          // La disponibilidad de esta comprobación no invalida el perfil.
          return null;
        }
      })();
      final profile = await userService
          .getUser(loginUid, reportErrors: false, serverOnly: true)
          .timeout(const Duration(seconds: 5));
      final hasUsername = profile != null && profile.username.isNotEmpty;
      final hasArtists = profile != null && profile.topArtistNames.isNotEmpty;
      final cachedSetup = UserSetupCache.read(prefs, loginUid);
      final onboardingDone =
          hasArtists ||
          (cachedSetup?.onboardingDone ?? false) ||
          (prefs.getBool(OnboardingScreen.onboardingCompletedKey) ?? false);
      final photoSetupDone =
          onboardingDone ||
          (cachedSetup?.photoSetupDone ?? false) ||
          (prefs.getBool(PhotoSetupScreen.photoSetupDoneKey) ?? false);
      return (
        usernameSet: hasUsername,
        artistsSelected: hasArtists,
        onboardingDone: onboardingDone,
        photoSetupDone: photoSetupDone,
        deletionPending: await deletionPendingFuture,
      );
    },
    persistUserState: (uid, state) => UserSetupCache.write(
      prefs,
      uid,
      CachedUserSetupState(
        usernameSet: state.usernameSet,
        artistsSelected: state.artistsSelected,
        onboardingDone: state.onboardingDone,
        photoSetupDone: state.photoSetupDone,
      ),
    ),
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(appRouterNotifierProvider);
  return GoRouter(
    initialLocation: ref.watch(initialRouterLocationProvider),
    refreshListenable: notifier,
    observers: [appRouteObserver],
    redirect: (context, state) => appRedirect(notifier, state.matchedLocation),
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthScreen(
          accountDeletionNotice: state.uri.queryParameters['accountDeletion'],
        ),
      ),
      GoRoute(
        path: '/deleting-account',
        builder: (context, state) => const DeletingAccountScreen(),
      ),
      GoRoute(
        path: '/username-setup',
        builder: (context, state) => const UsernameSetupScreen(),
      ),
      GoRoute(
        path: '/artist-select',
        builder: (context, state) => const ArtistSelectorScreen(),
      ),
      GoRoute(
        path: '/artist-edit',
        builder: (context, state) =>
            const ArtistSelectorScreen(isEditMode: true),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/photo-setup',
        builder: (context, state) => const PhotoSetupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => MainScreen(
          initialPageIndex: MainScreen.pageIndexForTab(
            state.uri.queryParameters['tab'],
          ),
        ),
      ),
      GoRoute(path: '/profile/:uid', builder: buildUserProfileRoute),
      GoRoute(
        path: '/chat',
        redirect: (context, state) {
          final q = state.uri.queryParameters;
          if (q['chatId'] == null || q['otherUserId'] == null) {
            return '/';
          }
          return null;
        },
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return ChatScreen(
            chatId: q['chatId']!,
            otherUserName: q['otherUserName'] ?? '',
            otherUserId: q['otherUserId']!,
          );
        },
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const UserSearchScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: '/privacy-policy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/blocked-users',
        builder: (context, state) => const BlockedUsersScreen(),
      ),
    ],
  );
});
