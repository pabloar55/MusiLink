import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

class UserAvatarButton extends ConsumerWidget {
  const UserAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final appUser = ref.watch(currentUserProvider).asData?.value;
    final imageUrl = appUser?.photoUrl ?? '';

    return Tooltip(
      message: l10n.menuAccountOptions,
      child: InkWell(
        onTap: () => context.push('/settings'),
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: CircleAvatar(
            radius: 16,
            child: ClipOval(
              child: SizedBox.expand(
                child: UserProfilePhoto(
                  photoUrl: imageUrl,
                  fallback: const Icon(LucideIcons.user, size: 18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
