import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/terms_acceptance_provider.dart';
import 'package:musi_link/providers/user_setup_provider.dart';
import 'package:musi_link/services/group_chat_service.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/router/app_route_observer.dart';
import 'package:musi_link/screens/account_settings_screen.dart';
import 'package:musi_link/screens/deleting_account_screen.dart';
import 'package:musi_link/screens/blocked_users_screen.dart';
import 'package:musi_link/screens/auth_screen.dart';
import 'package:musi_link/screens/terms_acceptance_screen.dart';
import 'package:musi_link/screens/chat_screen.dart';
import 'package:musi_link/screens/group_chat_screen.dart';
import 'package:musi_link/screens/group_info_screen.dart';
import 'package:musi_link/screens/create_group_chat_screen.dart';
import 'package:musi_link/screens/main_screen.dart';
import 'package:musi_link/screens/onboarding_screen.dart';
import 'package:musi_link/screens/photo_setup_screen.dart';
import 'package:musi_link/screens/artist_selector_screen.dart';
import 'package:musi_link/screens/username_setup_screen.dart';
import 'package:musi_link/screens/user_profile_route_screen.dart';
import 'package:musi_link/screens/user_search_screen.dart';

// ── Router ──────────────────────────────────────────────────────

final initialRouterLocationProvider = Provider<String>((ref) => '/');

final appRouterNotifierProvider = Provider<AppRouterNotifier>((ref) {
  final notifier = AppRouterNotifier(
    auth: ref.watch(firebaseAuthProvider),
    setup: ref.watch(userSetupControllerProvider),
    terms: ref.watch(termsAcceptanceControllerProvider),
    initialState: ref.watch(userSetupBootstrapStateProvider),
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
        path: '/terms',
        builder: (context, state) => const TermsAcceptanceScreen(),
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
        routes: [
          // Hija de '/' para que un perfil abierto desde un enlace compartido
          // tenga la pantalla principal detrás al volver.
          GoRoute(path: 'u/:username', builder: buildUsernameProfileRoute),
        ],
      ),
      GoRoute(path: '/profile/:uid', builder: buildUserProfileRoute),
      GoRoute(
        path: '/new-group-chat',
        builder: (context, state) => const CreateGroupChatScreen(),
        routes: [
          GoRoute(
            path: 'name',
            redirect: (context, state) {
              final participants = state.extra;
              return participants is List<AppUser> &&
                      participants.map((user) => user.uid).toSet().length >=
                          2 &&
                      participants.length <
                          GroupChatService.maxGroupParticipants
                  ? null
                  : '/new-group-chat';
            },
            builder: (context, state) => NameGroupChatScreen(
              participants: state.extra! as List<AppUser>,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/group-chat/:chatId',
        builder: (context, state) => GroupChatScreen(
          chatId: state.pathParameters['chatId']!,
          initialGroup: state.extra is Chat ? state.extra! as Chat : null,
        ),
        routes: [
          GoRoute(
            path: 'info',
            builder: (context, state) =>
                GroupInfoScreen(chatId: state.pathParameters['chatId']!),
          ),
          GoRoute(
            path: 'add-members',
            builder: (context, state) =>
                AddGroupMembersScreen(chatId: state.pathParameters['chatId']!),
          ),
        ],
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
        path: '/blocked-users',
        builder: (context, state) => const BlockedUsersScreen(),
      ),
    ],
  );
});
