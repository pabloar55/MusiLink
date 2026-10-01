import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

class CompatibilityCard extends StatelessWidget {
  final AsyncValue<DiscoveryResult> value;

  const CompatibilityCard({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const SkeletonShimmer(child: SkeletonCompatibilityCard()),
      error: (_, _) => const SizedBox.shrink(),
      data: (result) => _CompatibilityCardContent(result: result),
    );
  }
}

class _CompatibilityCardContent extends StatefulWidget {
  final DiscoveryResult result;
  const _CompatibilityCardContent({required this.result});

  @override
  State<_CompatibilityCardContent> createState() =>
      _CompatibilityCardContentState();
}

class _CompatibilityCardContentState extends State<_CompatibilityCardContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _gaugeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTokens.durationSlow,
    )..forward();
    _gaugeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final score = widget.result.score;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.spaceXL),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gauge circular con score
            AnimatedBuilder(
              animation: _gaugeAnimation,
              builder: (ctx, child) => _CompatibilityGauge(
                score: score,
                progress: _gaugeAnimation.value,
                primaryColor: cs.primary,
                trackColor: cs.surfaceContainerHighest,
                onSurface: cs.onSurface,
                textTheme: tt,
              ),
            ),
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              l10n.profileCompatible,
              style: tt.bodySmall?.copyWith(letterSpacing: 0.5),
            ),

            // Artistas compartidos
            if (widget.result.sharedArtistNames.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceLG),
              _SectionLabel(
                label: l10n.profileSharedArtists,
                icon: LucideIcons.music,
              ),
              const SizedBox(height: AppTokens.spaceSM),
              _ChipWrap(
                items: widget.result.sharedArtistNames,
                color: cs.primary,
              ),
            ],

            // Géneros compartidos
            if (widget.result.sharedGenreNames.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceLG),
              _SectionLabel(
                label: l10n.profileSharedGenres,
                icon: LucideIcons.tag,
              ),
              const SizedBox(height: AppTokens.spaceSM),
              _ChipWrap(
                items: widget.result.sharedGenreNames,
                color: cs.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _CompatibilityGauge extends StatelessWidget {
  final double score;
  final double progress;
  final Color primaryColor;
  final Color trackColor;
  final Color onSurface;
  final TextTheme textTheme;

  const _CompatibilityGauge({
    required this.score,
    required this.progress,
    required this.primaryColor,
    required this.trackColor,
    required this.onSurface,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    const size = 110.0;
    final displayScore = (score * progress).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _GaugePainter(
              progress: (score / 100) * progress,
              primaryColor: primaryColor,
              trackColor: trackColor,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$displayScore%',
                style: textTheme.displaySmall?.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color trackColor;

  const _GaugePainter({
    required this.progress,
    required this.primaryColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = math.pi * 0.75;
    const sweepTotal = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotal,
      false,
      trackPaint,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepTotal * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress;
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: AppTokens.spaceXS),
        Text(
          label.toUpperCase(),
          style: tt.labelSmall?.copyWith(letterSpacing: 1.0),
        ),
      ],
    );
  }
}

class _ChipWrap extends StatelessWidget {
  final List<String> items;
  final Color color;

  const _ChipWrap({required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Wrap(
      spacing: AppTokens.spaceXS,
      runSpacing: AppTokens.spaceXS,
      alignment: WrapAlignment.center,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMD,
            vertical: AppTokens.spaceXS + 2,
          ),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(AppTokens.radiusFull),
            border: Border.all(color: color.withAlpha(80), width: 1),
          ),
          child: Text(
            item,
            style: tt.labelMedium?.copyWith(color: cs.onSurface),
          ),
        );
      }).toList(),
    );
  }
}
