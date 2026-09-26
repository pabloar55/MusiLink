import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/theme/app_theme.dart';

/// Shared composer for chats and private replies to songs.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onShareSong,
    this.canSend = true,
    this.autofocus = false,
    this.errorText,
    this.onChanged,
    this.backgroundColor,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onShareSong;
  final bool canSend;
  final bool autofocus;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (onShareSong != null)
              IconButton(
                onPressed: canSend ? onShareSong : null,
                icon: const Icon(LucideIcons.music),
                tooltip: l10n.chatShareSong,
              ),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: l10n.chatWriteMessage,
                  errorText: errorText,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: AppTheme.pillInputBorder,
                  enabledBorder: AppTheme.pillInputBorder,
                  focusedBorder: AppTheme.pillInputBorder,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: onChanged,
                onSubmitted: canSend ? (_) => onSend() : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: canSend ? onSend : null,
              tooltip: l10n.dailySongReplySend,
              icon: const Icon(LucideIcons.sendHorizontal500),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
