import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/theme/app_theme.dart';

const _kEmojis = ['❤️', '🔥', '👏', '😍', '💀'];

class FloatingReactionPicker extends StatefulWidget {
  final LayerLink layerLink;
  final bool isMe;
  final Map<String, List<String>> reactions;
  final String currentUid;
  final void Function(String emoji) onReact;
  final VoidCallback onDismiss;
  final bool reactionsEnabled;
  final VoidCallback? onReport;

  const FloatingReactionPicker({
    super.key,
    required this.layerLink,
    required this.isMe,
    required this.reactions,
    required this.currentUid,
    required this.onReact,
    required this.onDismiss,
    this.reactionsEnabled = true,
    this.onReport,
  });

  @override
  State<FloatingReactionPicker> createState() => _FloatingReactionPickerState();
}

class _FloatingReactionPickerState extends State<FloatingReactionPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scale = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignment = widget.isMe
        ? Alignment.bottomRight
        : Alignment.bottomLeft;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          showWhenUnlinked: false,
          targetAnchor: widget.isMe ? Alignment.topRight : Alignment.topLeft,
          followerAnchor: alignment,
          offset: const Offset(0, -AppTokens.spaceXS),
          child: Material(
            color: Colors.transparent,
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                alignment: alignment,
                child: ReactionPicker(
                  reactions: widget.reactions,
                  currentUid: widget.currentUid,
                  onReact: widget.onReact,
                  reactionsEnabled: widget.reactionsEnabled,
                  onReport: widget.onReport,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReactionPicker extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUid;
  final void Function(String emoji) onReact;
  final bool reactionsEnabled;
  final VoidCallback? onReport;

  const ReactionPicker({
    super.key,
    required this.reactions,
    required this.currentUid,
    required this.onReact,
    this.reactionsEnabled = true,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSM,
        vertical: AppTokens.spaceXS,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reactionsEnabled)
            ..._kEmojis.map((emoji) {
              final hasReacted =
                  reactions[emoji]?.contains(currentUid) ?? false;
              return GestureDetector(
                onTap: () => onReact(emoji),
                child: SizedBox(
                  width: AppTokens.minTouchTarget,
                  height: AppTokens.minTouchTarget,
                  child: Center(
                    child: AnimatedContainer(
                      duration: AppTokens.durationFast,
                      padding: const EdgeInsets.all(AppTokens.spaceXS + 2),
                      decoration: BoxDecoration(
                        color: hasReacted
                            ? cs.onSurface.withAlpha(25)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
              );
            }),
          if (onReport != null) ...[
            if (reactionsEnabled)
              SizedBox(
                height: 28,
                child: VerticalDivider(color: cs.outlineVariant),
              ),
            IconButton(
              key: const ValueKey('report-message-action'),
              onPressed: onReport,
              tooltip: AppLocalizations.of(context)!.reportMessageAction,
              icon: const Icon(LucideIcons.flag, size: 20),
              color: cs.error,
            ),
          ],
        ],
      ),
    );
  }
}

class ReactionRow extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUid;
  final void Function(String emoji)? onReact;

  const ReactionRow({
    super.key,
    required this.reactions,
    required this.currentUid,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sortedKeys = reactions.keys.toList()
      ..sort((a, b) => _kEmojis.indexOf(a).compareTo(_kEmojis.indexOf(b)));
    final totalCount = reactions.values.fold(
      0,
      (sum, list) => sum + list.length,
    );
    final allEmojis = sortedKeys.join(' ');
    final myEmoji = reactions.entries
        .where((e) => e.value.contains(currentUid))
        .map((e) => e.key)
        .firstOrNull;

    return GestureDetector(
      onTap: myEmoji != null && onReact != null
          ? () => onReact!(myEmoji)
          : null,
      child: AnimatedContainer(
        duration: AppTokens.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSM,
          vertical: AppTokens.spaceXS,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
          border: Border.all(color: cs.surface, width: 2),
        ),
        child: Text(
          totalCount > 1 ? '$allEmojis $totalCount' : allEmojis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
