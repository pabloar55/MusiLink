import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

/// The photo and names in the profile's collapsible app bar.
class ProfileHeader extends StatelessWidget {
  static const _expandedAvatarTopPadding = 18.0;
  static const _collapsedAvatarTopPadding = 8.0;

  final AppUser user;

  const ProfileHeader({super.key, required this.user});

  static double expandedHeight(BuildContext context, AppUser user) {
    final painter =
        TextPainter(
          text: TextSpan(
            text: user.displayName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 2,
          ellipsis: '…',
        )..layout(
          maxWidth: (MediaQuery.sizeOf(context).width - 48).clamp(
            1,
            double.infinity,
          ),
        );
    final height =
        _expandedAvatarTopPadding +
        100 +
        AppTokens.spaceMD +
        painter.height +
        20;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
    final distance = settings.maxExtent - settings.minExtent;
    final progress = distance > 0
        ? ((settings.maxExtent - settings.currentExtent) / distance).clamp(
            0.0,
            1.0,
          )
        : 1.0;
    final topInset = settings.minExtent - kToolbarHeight;
    final avatarSize = lerpDouble(100, 40, progress)!;
    final avatarTop =
        topInset +
        lerpDouble(
          _expandedAvatarTopPadding,
          _collapsedAvatarTopPadding,
          progress,
        )!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final avatarLeft = lerpDouble(
          (constraints.maxWidth - 100) / 2,
          56,
          progress,
        )!;
        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: avatarLeft,
                top: avatarTop,
                width: avatarSize,
                height: avatarSize,
                child: Container(
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surface,
                    ),
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
              ),
              // The original name disappears immediately, without a transition.
              if (progress == 0)
                Positioned(
                  top:
                      topInset +
                      _expandedAvatarTopPadding +
                      100 +
                      AppTokens.spaceMD,
                  left: 24,
                  right: 24,
                  child: Text(
                    user.displayName,
                    style: tt.headlineSmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (progress > 0)
                Positioned(
                  left: avatarLeft + avatarSize + 8,
                  right: 56,
                  top: avatarTop + (avatarSize - kToolbarHeight) / 2,
                  height: kToolbarHeight,
                  child: Opacity(
                    opacity: progress,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        user.displayName,
                        style: tt.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
