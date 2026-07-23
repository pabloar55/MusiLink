import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final blockedAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedUsersTitle)),
      body: blockedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.genericError)),
        data: (uids) {
          if (uids.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space2XL),
                child: Text(
                  l10n.blockedUsersEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: uids.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _BlockedUserTile(uid: uids[i]),
          );
        },
      ),
    );
  }
}

class _BlockedUserTile extends ConsumerWidget {
  final String uid;

  const _BlockedUserTile({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final userAsync = ref.watch(userStreamProvider(uid));
    final user = userAsync.asData?.value;
    final photoUrl = user?.photoUrl ?? '';
    final displayName = user?.displayName ?? uid;
    final username = user?.username ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS,
      ),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: cs.surfaceContainerHighest,
        child: ClipOval(
          child: SizedBox.expand(
            child: UserProfilePhoto(
              photoUrl: photoUrl,
              fallback: Icon(
                LucideIcons.user,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      title: Text(displayName),
      subtitle: username.isNotEmpty ? Text('@$username') : null,
      trailing: TextButton(
        onPressed: () async {
          await ref.read(friendServiceProvider).unblockUser(uid);
        },
        child: Text(l10n.blockUserUnblock),
      ),
    );
  }
}
