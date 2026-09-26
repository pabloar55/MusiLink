import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/chat/chat_input_bar.dart';
import 'package:musi_link/widgets/track_artwork.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

class DailySongReplySheet extends StatefulWidget {
  const DailySongReplySheet({
    super.key,
    required this.owner,
    required this.song,
    this.initialText = '',
  });

  final AppUser owner;
  final Track song;
  final String initialText;

  @override
  State<DailySongReplySheet> createState() => _DailySongReplySheetState();
}

class _DailySongReplySheetState extends State<DailySongReplySheet> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _submitted = false;

  void _submit() {
    final text = _controller.text.trim();
    if (_submitted ||
        text.isEmpty ||
        utf8.encode(text).length > ChatService.maxMessageBytes) {
      return;
    }
    _submitted = true;
    // Close immediately. The parent hands the reply to the chat service and
    // retains a failed draft independently of this route's lifetime.
    Navigator.of(context).pop(text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final text = _controller.text.trim();
    final tooLong = utf8.encode(text).length > ChatService.maxMessageBytes;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
              child: Row(
                children: [
                  UserCircleAvatar(
                    photoUrl: widget.owner.photoUrl,
                    name: widget.owner.displayName,
                    radius: 22,
                  ),
                  const SizedBox(width: AppTokens.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.owner.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (widget.owner.username.isNotEmpty)
                          Text(
                            '@${widget.owner.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Row(
                children: [
                  TrackArtwork(
                    imageUrl: widget.song.imageUrl,
                    width: 72,
                    height: 72,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                  ),
                  const SizedBox(width: AppTokens.spaceMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.dailySongTitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceXS),
                        Text(
                          widget.song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          widget.song.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ChatInputBar(
              controller: _controller,
              autofocus: true,
              backgroundColor: Colors.transparent,
              canSend: text.isNotEmpty && !tooLong,
              errorText: tooLong ? l10n.dailySongReplyTooLong : null,
              onChanged: (_) => setState(() {}),
              onSend: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
