import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/collapsible_avatar_header.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

/// The photo and names in the profile's collapsible app bar.
class ProfileHeader extends StatelessWidget {
  final AppUser user;

  const ProfileHeader({super.key, required this.user});

  static double expandedHeight(BuildContext context, AppUser user) =>
      CollapsibleAvatarHeader.expandedHeight(context, user.displayName);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CollapsibleAvatarHeader(
      name: user.displayName,
      avatarBuilder: (avatarSize, _) => Container(
        padding: EdgeInsets.all(avatarSize * 0.03),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, cs.primary.withAlpha(120)],
          ),
        ),
        child: Container(
          padding: EdgeInsets.all(avatarSize * 0.02),
          decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
          child: ClipOval(
            child: UserProfilePhoto(
              photoUrl: user.photoUrl,
              fallback: ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  LucideIcons.user,
                  size: avatarSize * 0.44,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
