import 'package:material_ui/material_ui.dart';
import 'package:musi_link/theme/app_theme.dart';

// ─── Shimmer provider ─────────────────────────────────────────────────────────

/// Wrap a group of skeleton widgets in this to drive their shared shimmer.
class SkeletonShimmer extends StatefulWidget {
  final Widget child;
  const SkeletonShimmer({super.key, required this.child});

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonData(controller: _ctrl, child: widget.child);
}

class _SkeletonData extends InheritedWidget {
  final AnimationController controller;
  const _SkeletonData({required this.controller, required super.child});

  static AnimationController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonData>()?.controller;

  @override
  bool updateShouldNotify(_SkeletonData old) => false;
}

// ─── Base box ─────────────────────────────────────────────────────────────────

/// Animated placeholder rectangle that pulses between two opacities.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ctrl = _SkeletonData.of(context);

    final base = cs.onSurface.withAlpha(22);
    final peak = cs.onSurface.withAlpha(55);

    Widget box(Color color) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );

    if (ctrl != null) {
      return AnimatedBuilder(
        animation: ctrl,
        builder: (_, _) => box(
          Color.lerp(base, peak, Curves.easeInOut.transform(ctrl.value))!,
        ),
      );
    }
    return box(base);
  }
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

class _SkeletonCircle extends StatelessWidget {
  final double radius;
  const _SkeletonCircle({required this.radius});

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: radius * 2, height: radius * 2, borderRadius: radius);
}

// ─── Composed skeletons ───────────────────────────────────────────────────────

/// Standard list tile: circle avatar + two text lines.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _SkeletonCircle(radius: 20),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 130, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Request tile: circle avatar + name line + trailing button shape.
class SkeletonRequestTile extends StatelessWidget {
  const SkeletonRequestTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _SkeletonCircle(radius: 20),
          SizedBox(width: 16),
          Expanded(child: SkeletonBox(width: 130, height: 14)),
          SizedBox(width: 8),
          SkeletonBox(
            width: 72,
            height: 32,
            borderRadius: AppTokens.radiusFull,
          ),
        ],
      ),
    );
  }
}

/// Chat list tile: circle avatar + name/time row + message line.
class SkeletonChatListTile extends StatelessWidget {
  const SkeletonChatListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _SkeletonCircle(radius: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 14)),
                    SizedBox(width: 8),
                    SkeletonBox(width: 36, height: 11),
                  ],
                ),
                SizedBox(height: 6),
                SkeletonBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Discovery card — matches UserDiscoveryCard layout.
class SkeletonDiscoveryCard extends StatelessWidget {
  const SkeletonDiscoveryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS,
      ),
      child: Padding(
        padding: EdgeInsets.all(AppTokens.spaceLG),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonCircle(radius: 26),
            SizedBox(width: AppTokens.spaceMD),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: SkeletonBox(height: 14)),
                      SizedBox(width: AppTokens.spaceSM),
                      SkeletonBox(
                        width: 36,
                        height: 20,
                        borderRadius: AppTokens.radiusFull,
                      ),
                    ],
                  ),
                  SizedBox(height: AppTokens.spaceSM),
                  SkeletonBox(height: 11),
                  SizedBox(height: AppTokens.spaceXS + 2),
                  SkeletonBox(width: 120, height: 11),
                ],
              ),
            ),
            SizedBox(width: AppTokens.spaceXS),
            SkeletonBox(width: 20, height: 20),
          ],
        ),
      ),
    );
  }
}

/// Artwork, title/artist lines and the "more" button shared by the daily song
/// cards.
class _SkeletonDailySongRow extends StatelessWidget {
  const _SkeletonDailySongRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonBox(width: 64, height: 64, borderRadius: 8),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 150, height: 14),
              SizedBox(height: 8),
              SkeletonBox(width: 100, height: 12),
            ],
          ),
        ),
        SizedBox(
          width: 48,
          child: Center(
            child: SkeletonBox(width: 22, height: 6, borderRadius: 3),
          ),
        ),
      ],
    );
  }
}

/// Daily song card — matches DailySongCard layout.
class SkeletonDailySongCard extends StatelessWidget {
  const SkeletonDailySongCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: _SkeletonDailySongRow(),
      ),
    );
  }
}

/// Friend daily song card — matches FriendDailySongCard layout.
class SkeletonFriendDailySongCard extends StatelessWidget {
  const SkeletonFriendDailySongCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SkeletonCircle(radius: 14),
                SizedBox(width: 8),
                SkeletonBox(width: 110, height: 12),
              ],
            ),
            SizedBox(height: 12),
            _SkeletonDailySongRow(),
            SizedBox(height: 8),
            // Reply pill + like button.
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(child: SkeletonBox(height: 40, borderRadius: 20)),
                  SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    child: Center(child: _SkeletonCircle(radius: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compatibility card — matches CompatibilityCard layout.
class SkeletonCompatibilityCard extends StatelessWidget {
  const SkeletonCompatibilityCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.symmetric(horizontal: AppTokens.spaceLG),
      child: Padding(
        padding: EdgeInsets.all(AppTokens.spaceLG),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SkeletonCircle(radius: 42),
                SizedBox(height: AppTokens.spaceSM),
                SkeletonBox(width: 64, height: 12),
              ],
            ),
            SizedBox(width: AppTokens.spaceLG),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(width: 120, height: 11),
                  SizedBox(height: AppTokens.spaceSM),
                  Row(
                    children: [
                      SkeletonBox(
                        width: 70,
                        height: 28,
                        borderRadius: AppTokens.radiusFull,
                      ),
                      SizedBox(width: AppTokens.spaceXS),
                      SkeletonBox(
                        width: 56,
                        height: 28,
                        borderRadius: AppTokens.radiusFull,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Song search tile — square album art + title + artist line.
class SkeletonSongTile extends StatelessWidget {
  const SkeletonSongTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SkeletonBox(width: 48, height: 48, borderRadius: 4),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14, width: 150),
                SizedBox(height: 6),
                SkeletonBox(width: 110, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stats tile — matches TrackTile / ArtistTile layout.
class SkeletonStatsTile extends StatelessWidget {
  const SkeletonStatsTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS + 2,
      ),
      child: Row(
        children: [
          SkeletonBox(width: 28, height: 16),
          SizedBox(width: AppTokens.spaceSM),
          SkeletonBox(width: 52, height: 52, borderRadius: AppTokens.radiusSM),
          SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14),
                SizedBox(height: 4),
                SkeletonBox(width: 110, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two side-by-side button shapes — for FriendshipButtons initial load.
class SkeletonFriendshipButtons extends StatelessWidget {
  const SkeletonFriendshipButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: SkeletonBox(height: 40, borderRadius: AppTokens.radiusFull),
        ),
        SizedBox(width: 8),
        Expanded(
          child: SkeletonBox(height: 40, borderRadius: AppTokens.radiusFull),
        ),
      ],
    );
  }
}

/// Daily song tab loading layout — own card with its actions + section title
/// + friend cards.
class SkeletonDailySongTab extends StatelessWidget {
  const SkeletonDailySongTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBox(width: 160, height: 18, borderRadius: 4),
        ),
        const SizedBox(height: 12),
        const SkeletonDailySongCard(),
        const SizedBox(height: 4),
        // Likes + choose song buttons.
        const SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(width: 80, height: 14),
              SizedBox(width: 32),
              SkeletonBox(width: 170, height: 14),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBox(width: 180, height: 18, borderRadius: 4),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SkeletonFriendDailySongCard(),
          ),
        ),
      ],
    );
  }
}

/// Chat message list skeleton — alternating left/right bubble shapes.
class SkeletonChatMessages extends StatelessWidget {
  const SkeletonChatMessages({super.key});

  @override
  Widget build(BuildContext context) {
    const bubbles = [
      (width: 200.0, isMe: false),
      (width: 140.0, isMe: true),
      (width: 220.0, isMe: false),
      (width: 160.0, isMe: false),
      (width: 100.0, isMe: true),
      (width: 180.0, isMe: true),
      (width: 240.0, isMe: false),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      reverse: true,
      children: bubbles.map((b) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(
            alignment: b.isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: SkeletonBox(width: b.width, height: 40, borderRadius: 16),
          ),
        );
      }).toList(),
    );
  }
}
