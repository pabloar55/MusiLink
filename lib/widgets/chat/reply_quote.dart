import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/theme/app_theme.dart';

/// Cita del mensaje respondido: dentro de una burbuja o sobre el compositor.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.senderName,
    required this.text,
    required this.accentColor,
    required this.textColor,
    required this.backgroundColor,
    this.isTrack = false,
    this.maxLines = 2,
    this.onTap,
    this.onClose,
  });

  final String senderName;
  final String text;
  final Color accentColor;
  final Color textColor;
  final Color backgroundColor;
  final bool isTrack;
  final int maxLines;

  /// Lleva al mensaje citado.
  final VoidCallback? onTap;

  /// Muestra el botón para descartar la respuesta en curso.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _buildQuote(context, tt),
    );
  }

  Widget _buildQuote(BuildContext context, TextTheme tt) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusSM),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(left: BorderSide(color: accentColor, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceSM,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTrack) ...[
                          Icon(LucideIcons.music, size: 12, color: textColor),
                          const SizedBox(width: AppTokens.spaceXS),
                        ],
                        Flexible(
                          child: Text(
                            text,
                            maxLines: isTrack ? 1 : maxLines,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(color: textColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(LucideIcons.x, size: 18),
                color: textColor,
                tooltip: AppLocalizations.of(context)!.chatReplyCancel,
              ),
          ],
        ),
      ),
    );
  }
}
