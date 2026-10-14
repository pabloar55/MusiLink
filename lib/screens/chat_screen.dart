import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/session_scope_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/router/app_route_observer.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/services/chat_composer_controller.dart';
import 'package:musi_link/services/chat_history_controller.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/services/user_future_cache.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/chat/chat_input_bar.dart';
import 'package:musi_link/widgets/chat/chat_message_list.dart';
import 'package:musi_link/widgets/chat/chat_message_locator.dart';
import 'package:musi_link/widgets/chat/message_reply_quote.dart';
import 'package:musi_link/widgets/chat/track_search_sheet.dart';
import 'package:musi_link/widgets/group_circle_avatar.dart';
import 'package:musi_link/widgets/report_reason_dialog.dart';
import 'package:musi_link/widgets/service_error_snackbar.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:go_router/go_router.dart';

/// Conversación individual o grupal con historial compartido.
class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final Chat? group;
  final String otherUserName;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    this.group,
    required this.otherUserName,
    required this.otherUserId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver, RouteAware, UserFutureCache {
  @override
  UserService get userService => ref.read(userServiceProvider);

  bool get _isGroup => widget.group != null;
  final _inputFocusNode = FocusNode();
  final _scrollController = ScrollController(keepScrollOffset: false);
  late final ChatHistoryController _history;
  late final ChatComposerController _composer;
  late final ChatMessageLocator _locator;
  late final ActiveChatNotifier _activeChatNotifier;
  late final Future<AppUser?> _otherUserFuture;
  ModalRoute<void>? _route;
  DateTime? _lastSeenTimestamp;
  String? _lastVisibleMessageId;
  bool _isRouteVisible = true;
  bool _isAppResumed = true;

  bool _isOtherUserDeleted = false;
  bool _isAtBottom = true;

  /// UID of the authenticated user from the Riverpod provider.
  /// Returns empty string if session was lost — message bubbles fall back to
  /// always showing "other" side, which is safe for the UI.
  String get _currentUid => ref.read(sessionUidProvider) ?? '';

  bool get _canInteractInChat =>
      _isGroup ||
      (ref
              .read(relationshipProvider(widget.otherUserId))
              .asData
              ?.value
              .canInteractInChat ??
          false);

  bool get _canMarkMessagesRead => _isRouteVisible && _isAppResumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isAppResumed =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _activeChatNotifier = ref.read(activeChatIdProvider.notifier);
    unawaited(
      ref
          .read(notificationServiceProvider)
          .cancelChatNotifications(widget.chatId),
    );
    _otherUserFuture = _isGroup
        ? Future.value(null)
        : ref.read(userServiceProvider).getUser(widget.otherUserId);
    _otherUserFuture.then((user) {
      if (!mounted) return;
      setState(() => _isOtherUserDeleted = user?.isDeleted ?? false);
    });
    _history = ChatHistoryController(
      service: ref.read(chatServiceProvider),
      chatId: widget.chatId,
      onMessages: _onMessagesUpdated,
      onError: _onHistoryError,
    )..addListener(_rebuild);
    unawaited(_history.start());
    _composer = ChatComposerController(
      service: ref.read(chatServiceProvider),
      chatId: widget.chatId,
      onSent: _scrollToBottom,
      onError: _showWriteError,
    )..addListener(_rebuild);
    _locator = ChatMessageLocator(
      history: _history,
      scrollController: _scrollController,
      onUnavailable: _showOriginalUnavailable,
    )..addListener(_rebuild);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _route)) return;
    if (_route != null) appRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() {
    _setRouteVisible(true);
  }

  @override
  void didPushNext() {
    _setRouteVisible(false);
  }

  @override
  void didPopNext() {
    _setRouteVisible(true);
  }

  @override
  void didPop() {
    _setRouteVisible(false);
  }

  void _setRouteVisible(bool visible) {
    _isRouteVisible = visible;
    // RouteObserver callbacks may run while Navigator is updating its pages.
    // Defer provider changes until that frame ends in both directions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_canMarkMessagesRead) {
        _activeChatNotifier.clearChat(widget.chatId);
        return;
      }
      _activeChatNotifier.setChat(widget.chatId);
      if (_canInteractInChat) _markMessagesAsRead();
      _scrollToBottom(animate: false);
      unawaited(
        ref
            .read(notificationServiceProvider)
            .cancelChatNotifications(widget.chatId),
      );
    });
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onHistoryError({required bool unavailable}) {
    if (!mounted) return;
    _showWriteError(null);
    if (unavailable) _leaveChat();
  }

  /// Reacciona a cada actualización del historial: lectura y desplazamiento.
  void _onMessagesUpdated({required bool isFirst}) {
    if (!mounted) return;
    final messages = _history.messages;
    final confirmed = messages.where((message) => !message.isPending);
    final latestTimestamp = confirmed.isEmpty ? null : confirmed.last.timestamp;
    final lastVisibleId = messages.lastOrNull?.id;
    final shouldScroll =
        lastVisibleId != null && lastVisibleId != _lastVisibleMessageId;
    _lastVisibleMessageId = lastVisibleId;
    final hasNewMessages =
        latestTimestamp != null &&
        (_lastSeenTimestamp == null ||
            latestTimestamp.isAfter(_lastSeenTimestamp!));
    if (hasNewMessages) {
      _lastSeenTimestamp = latestTimestamp;
      if (_canMarkMessagesRead && _canInteractInChat) {
        _markMessagesAsRead();
      }
    }
    if (shouldScroll && _isRouteVisible) {
      // Los envíos locales también desplazan la lista inmediatamente.
      _scrollToBottom(animate: !isFirst);
    }
  }

  void _markMessagesAsRead() {
    if (_isGroup) {
      final latest = _history.messages
          .where((message) => !message.isPending)
          .lastOrNull;
      if (latest != null) {
        unawaited(
          ref
              .read(groupChatServiceProvider)
              .markGroupMessagesAsRead(widget.chatId, latest.timestamp),
        );
      }
    } else {
      unawaited(
        ref.read(chatServiceProvider).markMessagesAsRead(widget.chatId),
      );
    }
  }

  @override
  void didChangeMetrics() {
    final bottomInset = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .viewInsets
        .bottom;
    if (bottomInset > 0 && _isAtBottom) {
      // El teclado ya tiene su propia animación; saltar sin animar evita el lag.
      _scrollToBottom(animate: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
    if (!_isAppResumed || !_isRouteVisible) {
      _activeChatNotifier.clearChat(widget.chatId);
      return;
    }
    _activeChatNotifier.setChat(widget.chatId);
    if (_canInteractInChat) _markMessagesAsRead();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeChatNotifier.clearChat(widget.chatId);
    });
    _history.dispose();
    _locator.dispose();
    _scrollController.removeListener(_onScroll);
    _composer.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _isAtBottom = pos.pixels <= pos.minScrollExtent + 80;
    // La página nueva mantiene el offset: reverse añade al extremo alto.
    if (pos.pixels >= pos.maxScrollExtent - 100) {
      unawaited(_history.loadMore());
    }
  }

  void _sendMessage() {
    if (_isOtherUserDeleted || !_canInteractInChat) return;
    unawaited(_composer.sendText());
  }

  void _startReply(Message message) {
    _composer.startReply(message);
    _inputFocusNode.requestFocus();
  }

  void _showOriginalUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.chatReplyOriginalUnavailable,
        ),
      ),
    );
  }

  void _showWriteError(Object? error) {
    final l10n = AppLocalizations.of(context)!;
    showServiceError(
      context,
      error,
      notAllowedMessage: _isGroup
          ? l10n.groupChatCannotSend
          : l10n.chatNotFriendsCannotSend,
    );
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (!position.hasContentDimensions) return;
      final bottom = position.minScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          bottom,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(bottom);
      }
    });
  }

  void _showTrackSearch() {
    if (_isOtherUserDeleted || !_canInteractInChat) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TrackSearchSheet(
        onTrackSelected: (track) {
          Navigator.of(context).pop();
          unawaited(_composer.sendTrack(track));
        },
      ),
    );
  }

  Future<void> _reportMessage(Message message) async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await showReportReasonDialog(
      context,
      title: l10n.reportMessageTitle,
    );
    if (reason == null || !mounted) return;
    try {
      final created = await ref
          .read(moderationServiceProvider)
          .reportMessage(
            chatId: widget.chatId,
            messageId: message.id,
            reason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created ? l10n.reportSubmitted : l10n.reportAlreadySubmitted,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showServiceError(context, error, fallbackMessage: l10n.reportSubmitError);
    }
  }

  void _openGroupInfo() {
    context.push('/group-chat/${Uri.encodeComponent(widget.chatId)}/info');
  }

  Future<void> _openOtherUserProfile() async {
    final nav = GoRouter.of(context);
    final user = await _otherUserFuture;
    if (user != null && !user.isDeleted && mounted) {
      unawaited(
        nav.push(userProfileLocation(user.uid, fromChat: true), extra: user),
      );
    }
  }

  void _leaveChat() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/?tab=messages');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isGroup) {
      ref.listen(relationshipProvider(widget.otherUserId), (previous, next) {
        final couldInteract =
            previous?.asData?.value.canInteractInChat ?? false;
        final canInteractNow = next.asData?.value.canInteractInChat ?? false;
        if (!couldInteract &&
            canInteractNow &&
            _canMarkMessagesRead &&
            _history.messages.isNotEmpty) {
          _markMessagesAsRead();
        }
      });
    }

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final relationship = _isGroup
        ? null
        : ref.watch(relationshipProvider(widget.otherUserId));
    final relationshipResult = relationship?.asData?.value;
    final isBlockedByMe =
        relationshipResult?.status == RelationshipStatus.blocked;
    final canInteract =
        _isGroup || (relationshipResult?.canInteractInChat ?? false);
    final canPop = GoRouter.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveChat();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isGroup ? _openGroupInfo : _openOtherUserProfile,
            child: AppBar(
              backgroundColor: colorScheme.surfaceContainerLow,
              leading: canPop ? null : BackButton(onPressed: _leaveChat),
              centerTitle: false,
              titleSpacing: 0,
              title: _isGroup
                  ? Row(
                      children: [
                        GroupCircleAvatar(
                          photoUrl: widget.group!.photoUrl,
                          radius: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.group!.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                l10n.groupChatMembers(
                                  widget.group!.participants.length,
                                ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : FutureBuilder<AppUser?>(
                      future: _otherUserFuture,
                      builder: (context, snapshot) {
                        final user = snapshot.data;
                        final name = user?.displayName ?? widget.otherUserName;
                        final photoUrl = user?.photoUrl ?? '';

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserCircleAvatar(
                              photoUrl: photoUrl,
                              name: name,
                              radius: 16,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
        body: Column(
          children: [
            // Lista de mensajes
            Expanded(
              child: ChatMessageList(
                messages: _history.messages,
                isInitialLoading: _history.isInitialLoading,
                isLoadingMore: _history.isLoadingMore,
                scrollController: _scrollController,
                locator: _locator,
                chatId: widget.chatId,
                chatService: ref.read(chatServiceProvider),
                currentUid: _currentUid,
                isGroup: _isGroup,
                reactionsEnabled: canInteract,
                senderFuture: _senderFuture,
                fallbackSenderName: _fallbackSenderName(l10n),
                onReport: _reportMessage,
                onReply: canInteract && !_isOtherUserDeleted
                    ? _startReply
                    : null,
              ),
            ),
            if (_isOtherUserDeleted)
              _buildDeletedAccountBar(colorScheme, l10n)
            else if (relationship?.isLoading ?? false)
              _buildInputBar(canSend: false)
            else if (isBlockedByMe)
              _buildBlockedChatBar(colorScheme, l10n)
            else if (!canInteract)
              _buildNotFriendsChatBar(colorScheme, l10n)
            else
              _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Future<AppUser?> _senderFuture(String senderId) =>
      _isGroup ? getUserFuture(senderId) : _otherUserFuture;

  String _fallbackSenderName(AppLocalizations l10n) =>
      _isGroup ? l10n.socialUser : widget.otherUserName;

  Widget _buildInputBar({bool canSend = true}) {
    final replyingTo = _composer.replyingTo;
    final colorScheme = Theme.of(context).colorScheme;
    return ChatInputBar(
      controller: _composer.textController,
      focusNode: _inputFocusNode,
      canSend: canSend,
      onSend: _sendMessage,
      onShareSong: _showTrackSearch,
      header: replyingTo == null
          ? null
          : MessageReplyQuote(
              reply: replyingTo.toReply(),
              currentUid: _currentUid,
              senderFuture: _senderFuture,
              fallbackSenderName: _fallbackSenderName(
                AppLocalizations.of(context)!,
              ),
              accentColor: colorScheme.primary,
              textColor: colorScheme.onSurfaceVariant,
              backgroundColor: colorScheme.surfaceContainerHighest,
              maxLines: 1,
              onClose: _composer.cancelReply,
            ),
    );
  }

  Widget _buildDeletedAccountBar(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          l10n.chatDeletedUser,
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildBlockedChatBar(ColorScheme colorScheme, AppLocalizations l10n) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          l10n.chatBlockedCannotSend,
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildNotFriendsChatBar(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          l10n.chatNotFriendsCannotSend,
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
