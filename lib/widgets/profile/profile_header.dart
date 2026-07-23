import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

class ProfileHeader extends StatelessWidget {
  final AppUser user;

  const ProfileHeader({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar con anillo decorativo
        Stack(
          alignment: Alignment.center,
          children: [
            // Anillo exterior con color primario
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.primary.withAlpha(120)],
                ),
              ),
            ),
            // Avatar con borde interior (gap visual)
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surface,
              ),
            ),
            ClipOval(
              child: SizedBox(
                width: 90,
                height: 90,
                child: UserProfilePhoto(
                  photoUrl: user.photoUrl,
                  fallback: _avatarPlaceholder(cs),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMD),

        // Nombre de usuario
        Text(
          user.displayName,
          style: tt.headlineSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _avatarPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Icon(LucideIcons.user, size: 44, color: cs.onSurfaceVariant),
    );
  }
}
