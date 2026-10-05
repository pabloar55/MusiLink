import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:musi_link/theme/app_theme.dart';

/// A photo and a name that shrink into the toolbar as a pinned [SliverAppBar]
/// collapses. Use it as the app bar's flexible space.
class CollapsibleAvatarHeader extends StatelessWidget {
  static const _expandedAvatarSize = 100.0;
  static const _collapsedAvatarSize = 40.0;
  static const _expandedAvatarTopPadding = 18.0;
  static const _collapsedAvatarTopPadding = 8.0;

  final String name;

  /// Builds the photo at its current size. Progress goes from 0 (expanded) to
  /// 1 (collapsed).
  final Widget Function(double size, double progress) avatarBuilder;

  const CollapsibleAvatarHeader({
    super.key,
    required this.name,
    required this.avatarBuilder,
  });

  static double expandedHeight(BuildContext context, String name) {
    final painter =
        TextPainter(
          text: TextSpan(
            text: name,
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
        _expandedAvatarSize +
        AppTokens.spaceMD +
        painter.height +
        20;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
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
    final avatarSize = lerpDouble(
      _expandedAvatarSize,
      _collapsedAvatarSize,
      progress,
    )!;
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
          (constraints.maxWidth - _expandedAvatarSize) / 2,
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
                child: avatarBuilder(avatarSize, progress),
              ),
              // The original name disappears immediately, without a transition.
              if (progress == 0)
                Positioned(
                  top:
                      topInset +
                      _expandedAvatarTopPadding +
                      _expandedAvatarSize +
                      AppTokens.spaceMD,
                  left: 24,
                  right: 24,
                  child: Text(
                    name,
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
                        name,
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
