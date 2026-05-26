import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/screens/account_settings_screen.dart';
import 'package:musi_link/screens/blocked_users_screen.dart';
import 'package:musi_link/screens/auth_screen.dart';
import 'package:musi_link/screens/privacy_policy_screen.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/screens/main_screen.dart';
import 'package:musi_link/screens/onboarding_screen.dart';
import 'package:musi_link/screens/photo_setup_screen.dart';
import 'package:musi_link/screens/artist_selector_screen.dart';
import 'package:musi_link/screens/username_setup_screen.dart';
import 'package:musi_link/screens/user_profile_screen.dart';
import 'package:musi_link/screens/user_search_screen.dart';

// ── Router ──────────────────────────────────────────────────────

final routerBootstrapStateProvider = Provider<AppRouterBootstrapState?>(
  (ref) => null,
);

final initialRouterLocationProvider = Provider<String>((ref) => '/');

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  final userService = ref.read(userServiceProvider);
  final notifier = AppRouterNotifier(
    auth: ref.watch(firebaseAuthProvider),
    initialState: ref.watch(routerBootstrapStateProvider),
    fetchUserState: (loginUid) async {
      final profile = await userService.getUser(loginUid, reportErrors: false);
      final hasUsername = profile != null && profile.username.isNotEmpty;
      final hasArtists = profile != null && profile.topArtistNames.isNotEmpty;
      return (
        usernameSet: hasUsername,
        artistsSelected: hasArtists,
        onboardingDone: hasArtists,
        photoSetupDone: hasArtists,
      );
    },
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(appRouterNotifierProvider);
  return GoRouter(
    initialLocation: ref.watch(initialRouterLocationProvider),
    refreshListenable: notifier,
    redirect: (context, state) => appRedirect(notifier, state.matchedLocation),
    routes: [
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
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
      GoRoute(
        path: '/profile',
        redirect: (context, state) {
          final extra = state.extra;
          if (extra is! AppUser && extra is! DiscoveryResult) return '/';
          return null;
        },
        builder: (context, state) {
          final extra = state.extra;
          final fromChat =
              state.uri.queryParameters['fromChat'] == 'true';
          if (extra is DiscoveryResult) {
            return UserProfileScreen(
              user: extra.user,
              initialCompatibility: extra,
              fromChat: fromChat,
            );
          }
          return UserProfileScreen(
            user: extra! as AppUser,
            fromChat: fromChat,
          );
        },
      ),
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
