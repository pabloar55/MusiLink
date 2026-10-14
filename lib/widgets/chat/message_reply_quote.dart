import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/message_reply.dart';
import 'package:musi_link/widgets/chat/reply_quote.dart';

/// [ReplyQuote] de un mensaje del chat, con el nombre de su autor resuelto.
class MessageReplyQuote extends StatelessWidget {
  const MessageReplyQuote({
    super.key,
    required this.reply,
    required this.currentUid,
    required this.senderFuture,
    required this.fallbackSenderName,
    required this.accentColor,
    required this.textColor,
    required this.backgroundColor,
    this.maxLines = 2,
    this.onTap,
    this.onClose,
  });

  final MessageReply reply;
  final String currentUid;

  /// Perfil de quien envió un mensaje del chat.
  final Future<AppUser?> Function(String senderId) senderFuture;

  /// Nombre mientras el perfil no está disponible.
  final String fallbackSenderName;
  final Color accentColor;
  final Color textColor;
  final Color backgroundColor;
  final int maxLines;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final isMine = reply.senderId == currentUid;
    return FutureBuilder<AppUser?>(
      future: isMine ? null : senderFuture(reply.senderId),
      builder: (context, snapshot) => ReplyQuote(
        senderName: isMine
            ? AppLocalizations.of(context)!.groupChatYou
            : snapshot.data?.displayName ?? fallbackSenderName,
        text: reply.text,
        isTrack: reply.isTrack,
        accentColor: accentColor,
        textColor: textColor,
        backgroundColor: backgroundColor,
        maxLines: maxLines,
        onTap: onTap,
        onClose: onClose,
      ),
    );
  }
}
