import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/chat/chat_message_locator.dart';
import 'package:musi_link/widgets/chat/message_bubble.dart';
import 'package:musi_link/widgets/chat/message_reply_quote.dart';
import 'package:musi_link/widgets/chat/message_sender_avatar.dart';
import 'package:musi_link/widgets/chat/swipe_to_reply.dart';
import 'package:musi_link/widgets/chat/track_bubble.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

/// Historial de un chat, agrupado por día y por remitente, con sus estados de
/// carga inicial, vacío y paginación.
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.isInitialLoading,
    required this.isLoadingMore,
    required this.scrollController,
    required this.locator,
    required this.chatId,
    required this.chatService,
    required this.currentUid,
    required this.isGroup,
    required this.reactionsEnabled,
    required this.senderFuture,
    required this.fallbackSenderName,
    required this.onReport,
    this.onReply,
  });

  /// Del más antiguo al más reciente.
  final List<Message> messages;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final ScrollController scrollController;

  /// Identifica las filas y lleva hasta el mensaje citado al tocar una cita.
  final ChatMessageLocator locator;
  final String chatId;
  final ChatService chatService;
  final String currentUid;
  final bool isGroup;
  final bool reactionsEnabled;

  /// Perfil de quien envió un mensaje del chat.
  final Future<AppUser?> Function(String senderId) senderFuture;

  /// Nombre mientras el perfil no está disponible.
  final String fallbackSenderName;
  final ValueChanged<Message> onReport;

  /// Sin valor, los mensajes no admiten respuesta.
  final ValueChanged<Message>? onReply;

  @override
  Widget build(BuildContext context) {
    if (isInitialLoading) {
      return const SkeletonShimmer(child: SkeletonChatMessages());
    }

    final colorScheme = Theme.of(context).colorScheme;
    if (messages.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.chatSendFirst,
          style: TextStyle(color: colorScheme.onSurface.withAlpha(120)),
        ),
      );
    }

    return Column(
      children: [
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: messages.length,
            itemBuilder: (context, index) => _buildMessage(
              context,
              colorScheme,
              messages.length - 1 - index,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(
    BuildContext context,
    ColorScheme colorScheme,
    int messageIndex,
  ) {
    final msg = messages[messageIndex];
    final isMe = msg.senderId == currentUid;
    final showDateSeparator =
        messageIndex == 0 ||
        !_isSameCalendarDay(
          msg.timestamp,
          messages[messageIndex - 1].timestamp,
        );
    // Mensajes seguidos de una misma persona en el mismo día forman
    // un bloque: nombre en el primero y foto en el último.
    final startsSenderRun =
        showDateSeparator ||
        messages[messageIndex - 1].senderId != msg.senderId;
    final next = messageIndex + 1 < messages.length
        ? messages[messageIndex + 1]
        : null;
    final endsSenderRun =
        next == null ||
        next.senderId != msg.senderId ||
        !_isSameCalendarDay(msg.timestamp, next.timestamp);
    final senderAvatar = isMe
        ? null
        : !endsSenderRun
        ? const MessageSenderAvatar.spacer()
        : MessageSenderAvatar(
            userFuture: senderFuture(msg.senderId),
            fallbackName: fallbackSenderName,
          );
    final replyTo = msg.replyTo;
    final replyQuote = replyTo == null
        ? null
        : MessageReplyQuote(
            reply: replyTo,
            currentUid: currentUid,
            senderFuture: senderFuture,
            fallbackSenderName: fallbackSenderName,
            accentColor: isMe ? colorScheme.onPrimary : colorScheme.primary,
            textColor: isMe
                ? colorScheme.onPrimary.withAlpha(220)
                : colorScheme.onSurfaceVariant,
            backgroundColor:
                (isMe ? colorScheme.onPrimary : colorScheme.onSurface)
                    .withAlpha(28),
            onTap: () => locator.show(replyTo.messageId),
          );
    final onReport = !isMe && !msg.isPending ? () => this.onReport(msg) : null;
    final onReply = this.onReply;

    final messageBubble = msg.isTrack
        ? TrackBubble(
            message: msg,
            isMe: isMe,
            colorScheme: colorScheme,
            currentUid: currentUid,
            chatId: chatId,
            chatService: chatService,
            showReceipts: !isGroup,
            reactionsEnabled: reactionsEnabled && !msg.isPending,
            onReport: onReport,
            senderAvatar: senderAvatar,
            replyQuote: replyQuote,
          )
        : MessageBubble(
            message: msg,
            isMe: isMe,
            colorScheme: colorScheme,
            currentUid: currentUid,
            chatId: chatId,
            chatService: chatService,
            showReceipts: !isGroup,
            reactionsEnabled: reactionsEnabled && !msg.isPending,
            onReport: onReport,
            senderAvatar: senderAvatar,
            replyQuote: replyQuote,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateSeparator)
          _buildDateSeparator(context, msg.timestamp, colorScheme),
        if (isGroup && !isMe && startsSenderRun)
          Padding(
            padding: const EdgeInsets.only(
              left: MessageSenderAvatar.extent + 8,
              top: 8,
            ),
            child: FutureBuilder<AppUser?>(
              future: senderFuture(msg.senderId),
              builder: (context, snapshot) => Text(
                snapshot.data?.displayName ?? fallbackSenderName,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colorScheme.primary),
              ),
            ),
          ),
        AnimatedContainer(
          key: locator.keyFor(msg.id),
          duration: AppTokens.durationSlow,
          decoration: BoxDecoration(
            color: colorScheme.primary.withAlpha(
              msg.id == locator.highlightedMessageId ? 40 : 0,
            ),
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          ),
          child: SwipeToReply(
            onReply: onReply != null && !msg.isPending
                ? () => onReply(msg)
                : null,
            child: messageBubble,
          ),
        ),
      ],
    );
  }

  bool _isSameCalendarDay(DateTime first, DateTime second) {
    final localFirst = first.toLocal();
    final localSecond = second.toLocal();
    return localFirst.year == localSecond.year &&
        localFirst.month == localSecond.month &&
        localFirst.day == localSecond.day;
  }

  Widget _buildDateSeparator(
    BuildContext context,
    DateTime timestamp,
    ColorScheme colorScheme,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final localDate = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );
    final daysAgo = today.difference(messageDate).inDays;
    final label = switch (daysAgo) {
      0 => l10n.chatDateToday,
      1 => l10n.chatDateYesterday,
      _ => MaterialLocalizations.of(context).formatMediumDate(localDate),
    };

    return Center(
      child: Container(
        key: ValueKey(
          'chat-date-${localDate.year}-${localDate.month}-${localDate.day}',
        ),
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
