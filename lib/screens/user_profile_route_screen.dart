import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/user_profile_screen.dart';

Widget buildUserProfileRoute(BuildContext _, GoRouterState state) {
  final uid = state.pathParameters['uid'] ?? '';
  final extra = state.extra;
  final initialCompatibility = extra is DiscoveryResult && extra.user.uid == uid
      ? extra
      : null;
  final initialUser = switch (extra) {
    final AppUser user when user.uid == uid => user,
    final DiscoveryResult result when result.user.uid == uid => result.user,
    _ => null,
  };

  return UserProfileRouteScreen(
    uid: uid,
    initialUser: initialUser,
    initialCompatibility: initialCompatibility,
    fromChat: state.uri.queryParameters['fromChat'] == 'true',
  );
}

class UserProfileRouteScreen extends ConsumerWidget {
  const UserProfileRouteScreen({
    super.key,
    required this.uid,
    this.initialUser,
    this.initialCompatibility,
    this.fromChat = false,
  });

  final String uid;
  final AppUser? initialUser;
  final DiscoveryResult? initialCompatibility;
  final bool fromChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedUser = initialUser;
    if (cachedUser != null && cachedUser.uid == uid) {
      return UserProfileScreen(
        user: cachedUser,
        initialCompatibility: initialCompatibility,
        fromChat: fromChat,
      );
    }

    if (uid.isEmpty) return const _ProfileLoadFailure();

    return ref
        .watch(userStreamProvider(uid))
        .when(
          data: (user) => user == null
              ? const _ProfileLoadFailure()
              : UserProfileScreen(
                  user: user,
                  initialCompatibility: initialCompatibility,
                  fromChat: fromChat,
                ),
          loading: () => const _ProfileLoadingScreen(),
          error: (_, _) => _ProfileLoadFailure(
            onRetry: () => ref.invalidate(userStreamProvider(uid)),
          ),
        );
  }
}

class _ProfileLoadingScreen extends StatelessWidget {
  const _ProfileLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.profileTitle)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ProfileLoadFailure extends StatelessWidget {
  const _ProfileLoadFailure({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.genericError, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(l10n.dailySongRetry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
