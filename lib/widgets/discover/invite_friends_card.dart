import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/app_invite_service.dart';

class InviteFriendsCard extends ConsumerWidget {
  const InviteFriendsCard({super.key});

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final username = ref.read(currentUserProvider).asData?.value?.username;
    final message = username == null || username.isEmpty
        ? l10n.inviteMessageNoUsername(AppInviteService.inviteUrl)
        : l10n.inviteMessage(username, AppInviteService.inviteUrl);
    // iPad ancla el panel de compartir a la posición del botón.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    final result = await ref
        .read(appInviteServiceProvider)
        .share(message, origin: origin);
    if (result != AppInviteResult.copied) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.inviteLinkCopied)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              LucideIcons.userPlus,
              size: 48,
              color: colorScheme.onSurfaceVariant.withAlpha(128),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.inviteFriendsTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.dailySongNoFriends,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withAlpha(180),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _invite(context, ref),
              icon: const Icon(LucideIcons.share2),
              label: Text(l10n.inviteFriendsButton),
            ),
          ],
        ),
      ),
    );
  }
}
