import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/router/app_route_observer.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/chat/message_bubble.dart';
import 'package:musi_link/widgets/chat/track_bubble.dart';
import 'package:musi_link/widgets/chat/track_search_sheet.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:go_router/go_router.dart';

/// Pantalla de conversación individual.
class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController(keepScrollOffset: false);
  StreamSubscription<List<Message>>? _messagesSubscription;
  late final ActiveChatNotifier _activeChatNotifier;
  late final Future<AppUser?> _otherUserFuture;
  ModalRoute<void>? _route;
  DateTime? _lastSeenTimestamp;
  bool _isRouteVisible = true;
  bool _isAppResumed = true;

  /// Timestamp de borrado suave derivado del documento del chat en Firestore.
  /// Se resuelve de forma asíncrona en _initMessagesStream antes de suscribirse.
  DateTime? _deletedSince;

  bool _isOtherUserDeleted = false;

  // Paginación: lista única de mensajes acumulados.
  List<Message> _allMessages = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _isAtBottom = true;

  /// UID of the authenticated user from the Riverpod provider.
  /// Returns empty string if session was lost — message bubbles fall back to
  /// always showing "other" side, which is safe for the UI.
  String get _currentUid =>
      ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  bool get _canInteractInChat =>
      ref
          .read(relationshipProvider(widget.otherUserId))
          .asData
          ?.value
          .canInteractInChat ??
      false;

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
    _otherUserFuture = ref
        .read(userServiceProvider)
        .getUser(widget.otherUserId);
    _otherUserFuture.then((user) {
      if (!mounted) return;
      setState(() => _isOtherUserDeleted = user?.isDeleted ?? false);
    });
    unawaited(_initMessagesStream());
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

  /// Lee el chat de Firestore para obtener deletedAt[currentUid] y luego
  /// arranca la suscripción de mensajes. Al hacerlo aquí (en lugar de tomar
  /// el valor de la URL), todas las rutas de entrada al chat son correctas:
  /// lista de mensajes, perfil de usuario y notificaciones.
  ///
  /// Si Firestore falla, no arranca el stream sin filtro (lo que mostraría
  /// mensajes borrados). En cambio muestra genericError y sale del chat.
  Future<void> _initMessagesStream() async {
    try {
      _deletedSince = await ref
          .read(chatServiceProvider)
          .getDeletedSince(widget.chatId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.genericError)),
      );
      _leaveChat();
      return;
    }
    if (!mounted) return;

    final stream = ref
        .read(chatServiceProvider)
        .getMessages(widget.chatId, since: _deletedSince);
    _messagesSubscription = stream.listen(_onMessagesUpdated);
  }

  void _onMessagesUpdated(List<Message> streamMessages) {
    if (!mounted) return;
    final isFirst = _isInitialLoading;
    final latestTimestamp = streamMessages.isEmpty
        ? null
        : streamMessages.last.timestamp;
    final hasNewMessages =
        latestTimestamp != null &&
        (_lastSeenTimestamp == null ||
            latestTimestamp.isAfter(_lastSeenTimestamp!));
    setState(() {
      if (streamMessages.isNotEmpty) {
        // Preservar mensajes más antiguos ya cargados por paginación.
        final oldestStreamTimestamp = streamMessages.first.timestamp;
        final preserved = _allMessages
            .where((m) => m.timestamp.isBefore(oldestStreamTimestamp))
            .toList();
        _allMessages = [...preserved, ...streamMessages];
      } else {
        _allMessages = [];
      }
      _isInitialLoading = false;
      // Si la primera carga tiene menos del límite de página, no hay mensajes más antiguos.
      if (isFirst) {
        _hasMoreMessages =
            streamMessages.length >= ChatService.messagesPageSize;
      }
    });
    if (hasNewMessages) {
      _lastSeenTimestamp = latestTimestamp;
      if (_canMarkMessagesRead && _canInteractInChat) {
        _markMessagesAsRead();
      }
      if (_isRouteVisible) {
        // Primera carga: saltar sin animación para no ver el scroll desde arriba.
        _scrollToBottom(animate: !isFirst);
      }
    }
  }

  void _markMessagesAsRead() {
    unawaited(ref.read(chatServiceProvider).markMessagesAsRead(widget.chatId));
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
    _messagesSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _isAtBottom = pos.pixels <= pos.minScrollExtent + 80;
    if (pos.pixels >= pos.maxScrollExtent - 100 &&
        !_isLoadingMore &&
        _hasMoreMessages) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_allMessages.isEmpty) return;
    final cursor = _allMessages.first.timestamp;

    setState(() => _isLoadingMore = true);

    try {
      final older = await ref
          .read(chatServiceProvider)
          .loadOlderMessages(
            widget.chatId,
            before: cursor,
            since: _deletedSince,
          );

      if (!mounted) return;

      if (older.isEmpty) {
        setState(() {
          _isLoadingMore = false;
          _hasMoreMessages = false;
        });
        return;
      }

      // Capturar posición justo antes de modificar la lista para que el
      // delta refleje exactamente cuánto contenido se añade arriba.
      final oldOffset = _scrollController.hasClients
          ? _scrollController.offset
          : 0.0;
      final oldExtent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;

      final existingIds = _allMessages.map((m) => m.id).toSet();
      final newMessages = older
          .where((m) => !existingIds.contains(m.id))
          .toList();

      setState(() {
        _isLoadingMore = false;
        _allMessages = [...newMessages, ..._allMessages];
        if (older.length < ChatService.messagesPageSize) {
          _hasMoreMessages = false;
        }
      });

      // Ajustar scroll para que el contenido visible no salte.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final delta = _scrollController.position.maxScrollExtent - oldExtent;
          if (delta > 0) _scrollController.jumpTo(oldOffset + delta);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_isOtherUserDeleted || !_canInteractInChat) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      await ref
          .read(chatServiceProvider)
          .sendMessage(widget.chatId, text, otherUid: widget.otherUserId);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      if (_messageController.text.isEmpty) {
        _messageController.text = text;
        _messageController.selection = TextSelection.collapsed(
          offset: text.length,
        );
      }
      _showWriteError(e);
      return;
    } catch (_) {
      if (!mounted) return;
      if (_messageController.text.isEmpty) {
        _messageController.text = text;
        _messageController.selection = TextSelection.collapsed(
          offset: text.length,
        );
      }
      _showWriteError(null);
      return;
    }

    // Scroll al final tras enviar
    _scrollToBottom();
  }

  void _showWriteError(FirebaseException? error) {
    final l10n = AppLocalizations.of(context)!;
    final message = error?.code == 'permission-denied'
        ? l10n.chatNotFriendsCannotSend
        : l10n.genericError;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        onTrackSelected: (track) async {
          Navigator.of(context).pop();
          try {
            await ref
                .read(chatServiceProvider)
                .sendTrackMessage(
                  widget.chatId,
                  track,
                  otherUid: widget.otherUserId,
                );
            _scrollToBottom();
          } on FirebaseException catch (e) {
            if (mounted) _showWriteError(e);
          } catch (_) {
            if (mounted) _showWriteError(null);
          }
        },
      ),
    );
  }

  Future<void> _openOtherUserProfile() async {
    final nav = GoRouter.of(context);
    final user = await _otherUserFuture;
    if (user != null && !user.isDeleted && mounted) {
      unawaited(nav.push('/profile?fromChat=true', extra: user));
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
    ref.listen(relationshipProvider(widget.otherUserId), (previous, next) {
      final couldInteract = previous?.asData?.value.canInteractInChat ?? false;
      final canInteractNow = next.asData?.value.canInteractInChat ?? false;
      if (!couldInteract &&
          canInteractNow &&
          _canMarkMessagesRead &&
          _allMessages.isNotEmpty) {
        _markMessagesAsRead();
      }
    });

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final relationship = ref.watch(relationshipProvider(widget.otherUserId));
    final relationshipResult = relationship.asData?.value;
    final isBlockedByMe =
        relationshipResult?.status == RelationshipStatus.blocked;
    final canInteract = relationshipResult?.canInteractInChat ?? false;
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
            onTap: _openOtherUserProfile,
            child: AppBar(
              backgroundColor: colorScheme.surfaceContainerLow,
              leading: canPop ? null : BackButton(onPressed: _leaveChat),
              centerTitle: false,
              titleSpacing: 0,
              title: FutureBuilder<AppUser?>(
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
                        child: Text(name, overflow: TextOverflow.ellipsis),
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
            Expanded(child: _buildMessageList(colorScheme, l10n, canInteract)),
            if (_isOtherUserDeleted)
              _buildDeletedAccountBar(colorScheme, l10n)
            else if (relationship.isLoading)
              _buildRelationshipLoadingBar(colorScheme)
            else if (isBlockedByMe)
              _buildBlockedChatBar(colorScheme, l10n)
            else if (!canInteract)
              _buildNotFriendsChatBar(colorScheme, l10n)
            else
              _buildInputBar(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(
    ColorScheme colorScheme,
    AppLocalizations l10n,
    bool canInteract,
  ) {
    if (_isInitialLoading) {
      return const SkeletonShimmer(child: SkeletonChatMessages());
    }

    if (_allMessages.isEmpty) {
      return Center(
        child: Text(
          l10n.chatSendFirst,
          style: TextStyle(color: colorScheme.onSurface.withAlpha(120)),
        ),
      );
    }

    return Column(
      children: [
        if (_isLoadingMore)
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
            controller: _scrollController,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _allMessages.length,
            itemBuilder: (context, index) {
              final messageIndex = _allMessages.length - 1 - index;
              final msg = _allMessages[messageIndex];
              final isMe = msg.senderId == _currentUid;
              final showDateSeparator =
                  messageIndex == 0 ||
                  !_isSameCalendarDay(
                    msg.timestamp,
                    _allMessages[messageIndex - 1].timestamp,
                  );

              final messageBubble = msg.isTrack
                  ? TrackBubble(
                      message: msg,
                      isMe: isMe,
                      colorScheme: colorScheme,
                      currentUid: _currentUid,
                      chatId: widget.chatId,
                      chatService: ref.read(chatServiceProvider),
                      reactionsEnabled: canInteract,
                    )
                  : MessageBubble(
                      message: msg,
                      isMe: isMe,
                      colorScheme: colorScheme,
                      currentUid: _currentUid,
                      chatId: widget.chatId,
                      chatService: ref.read(chatServiceProvider),
                      reactionsEnabled: canInteract,
                    );

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDateSeparator)
                    _buildDateSeparator(context, msg.timestamp, colorScheme),
                  messageBubble,
                ],
              );
            },
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

  Widget _buildInputBar(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: _showTrackSearch,
              icon: const Icon(LucideIcons.music),
              tooltip: l10n.chatShareSong,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: l10n.chatWriteMessage,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sendMessage,
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

  Widget _buildRelationshipLoadingBar(ColorScheme colorScheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
