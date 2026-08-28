import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/spotify_url.dart';
import 'package:musi_link/widgets/chat/reaction_picker.dart';
import 'package:musi_link/widgets/track_artwork.dart';
import 'package:url_launcher/url_launcher.dart';

class TrackBubble extends ConsumerStatefulWidget {
  final Message message;
  final bool isMe;
  final ColorScheme colorScheme;
  final String currentUid;
  final String chatId;
  final ChatService chatService;
  final bool reactionsEnabled;

  const TrackBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.colorScheme,
    required this.currentUid,
    required this.chatId,
    required this.chatService,
    this.reactionsEnabled = true,
  });

  @override
  ConsumerState<TrackBubble> createState() => _TrackBubbleState();
}

class _TrackBubbleState extends ConsumerState<TrackBubble> {
  final _layerLink = LayerLink();
  OverlayEntry? _pickerEntry;
  @override
  void dispose() {
    _pickerEntry?.remove();
    _pickerEntry = null;
    super.dispose();
  }

  void _showPicker() {
    if (!widget.reactionsEnabled) return;
    _pickerEntry?.remove();
    _pickerEntry = OverlayEntry(
      builder: (_) => FloatingReactionPicker(
        layerLink: _layerLink,
        isMe: widget.isMe,
        reactions: widget.message.reactions,
        currentUid: widget.currentUid,
        onReact: _toggleReaction,
        onDismiss: () =>
            ref.read(activeReactionPickerProvider.notifier).close(),
      ),
    );
    Overlay.of(context).insert(_pickerEntry!);
  }

  void _hidePicker() {
    _pickerEntry?.remove();
    _pickerEntry = null;
  }

  void _toggleReaction(String emoji) {
    if (!widget.reactionsEnabled) return;
    widget.chatService.toggleReaction(widget.chatId, widget.message.id, emoji);
    ref.read(activeReactionPickerProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeReactionPickerProvider, (prev, next) {
      if (next == widget.message.id) {
        _showPicker();
      } else if (prev == widget.message.id) {
        _hidePicker();
      }
    });

    final cs = widget.colorScheme;
    final tt = Theme.of(context).textTheme;
    final track = widget.message.trackData!;
    final spotifyUri = parseSpotifyTrackUri(track.spotifyUrl);
    final time =
        '${widget.message.timestamp.hour.toString().padLeft(2, '0')}:${widget.message.timestamp.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: widget.reactionsEnabled
          ? () => ref
                .read(activeReactionPickerProvider.notifier)
                .toggle(widget.message.id)
          : null,
      child: Align(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: widget.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.spaceXS),
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: GestureDetector(
                    onTap: spotifyUri != null
                        ? () async {
                            if (await canLaunchUrl(spotifyUri)) {
                              await launchUrl(
                                spotifyUri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          }
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isMe
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(AppTokens.radiusLG),
                          topRight: const Radius.circular(AppTokens.radiusLG),
                          bottomLeft: Radius.circular(
                            widget.isMe ? AppTokens.radiusLG : 4,
                          ),
                          bottomRight: Radius.circular(
                            widget.isMe ? 4 : AppTokens.radiusLG,
                          ),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TrackArtwork(
                            imageUrl: track.imageUrl,
                            width: double.infinity,
                            height: 160,
                            iconSize: 56,
                          ),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTokens.spaceMD,
                              AppTokens.spaceSM + 2,
                              AppTokens.spaceMD,
                              AppTokens.spaceXS,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.titleSmall?.copyWith(
                                    color: widget.isMe
                                        ? cs.onPrimary
                                        : cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    color: widget.isMe
                                        ? cs.onPrimary.withAlpha(
                                            AppTokens.alphaMedium,
                                          )
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTokens.spaceMD,
                              0,
                              AppTokens.spaceMD,
                              AppTokens.spaceSM,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: tt.labelSmall?.copyWith(
                                    fontSize: 11,
                                    color: widget.isMe
                                        ? cs.onPrimary.withAlpha(
                                            AppTokens.alphaMedium,
                                          )
                                        : cs.onSurface.withAlpha(
                                            AppTokens.alphaLow,
                                          ),
                                  ),
                                ),
                                if (widget.isMe) ...[
                                  const SizedBox(width: AppTokens.spaceXS),
                                  Icon(
                                    widget.message.read
                                        ? LucideIcons.checkCheck
                                        : LucideIcons.check,
                                    size: 14,
                                    color: widget.message.read
                                        ? AppTokens.readReceiptColor
                                        : cs.onPrimary.withAlpha(
                                            AppTokens.alphaMedium,
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (widget.message.reactions.isNotEmpty)
                Transform.translate(
                  offset: const Offset(0, -6),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
                    child: ReactionRow(
                      reactions: widget.message.reactions,
                      currentUid: widget.currentUid,
                      onReact: widget.reactionsEnabled ? _toggleReaction : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
