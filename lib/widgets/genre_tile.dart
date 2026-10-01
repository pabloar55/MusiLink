import 'package:material_ui/material_ui.dart';
import 'package:musi_link/models/genre.dart';
import 'package:musi_link/theme/app_theme.dart';

class GenreTile extends StatefulWidget {
  final Genre genre;
  final int rank;

  const GenreTile({super.key, required this.genre, required this.rank});

  @override
  State<GenreTile> createState() => _GenreTileState();
}

class _GenreTileState extends State<GenreTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTokens.durationSlow,
    );
    _barAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    // Breve delay escalonado por rank para efecto en cascada
    Future.delayed(
      Duration(milliseconds: 60 * (widget.rank - 1)),
      () {
        if (mounted) _controller.forward();
      },
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
    final isTopThree = widget.rank <= 3;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Número de ranking
          SizedBox(
            width: 28,
            child: Text(
              '#${widget.rank}',
              textAlign: TextAlign.center,
              style: tt.labelMedium?.copyWith(
                fontWeight: isTopThree ? FontWeight.w700 : FontWeight.w400,
                color: isTopThree ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),

          // Barra de progreso + nombre + porcentaje
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.genre.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          color: isTopThree ? cs.onSurface : cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSM),
                    Text(
                      '${widget.genre.percentage.toStringAsFixed(1)}%',
                      style: tt.labelMedium?.copyWith(
                        color: isTopThree ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: isTopThree ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceXS),
                AnimatedBuilder(
                  animation: _barAnimation,
                  builder: (ctx, child) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.radiusFull),
                    child: LinearProgressIndicator(
                      value: (widget.genre.percentage / 100) * _barAnimation.value,
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        isTopThree ? cs.primary : cs.primary.withAlpha(160),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
