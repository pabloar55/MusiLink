import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
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
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController(keepScrollOffset: false);
  StreamSubscription<List<Message>>? _messagesSubscription;
  late final ActiveChatNotifier _activeChatNotifier;
  late final Future<AppUser?> _otherUserFuture;
  DateTime? _lastSeenTimestamp;

  /// Timestamp de borrado suave derivado del documento del chat en Firestore.
  /// Se resuelve de forma asíncrona en _initMessagesStream antes de suscribirse.
  DateTime? _deletedSince;

  bool _isOtherUserDeleted = false;
  bool _isBlockedByMe = false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeChatNotifier = ref.read(activeChatIdProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activeChatNotifier.setChat(widget.chatId);
    });
    unawaited(
      ref
          .read(notificationServiceProvider)
          .cancelChatNotifications(widget.chatId),
    );
    _otherUserFuture = ref.read(userServiceProvider).getUser(widget.otherUserId);
    _otherUserFuture.then((user) {
      if (!mounted) return;
      setState(() => _isOtherUserDeleted = user?.isDeleted ?? false);
    });
    unawaited(_initMessagesStream());
    _scrollController.addListener(_onScroll);
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
      _deletedSince =
          await ref.read(chatServiceProvider).getDeletedSince(widget.chatId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.genericError),
        ),
      );
      _leaveChat();
      return;
    }
    if (!mounted) return;

    final stream = ref.read(chatServiceProvider).getMessages(
      widget.chatId,
      since: _deletedSince,
    );
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
      if (!_isBlockedByMe) {
        unawaited(
          ref.read(chatServiceProvider).markMessagesAsRead(widget.chatId),
        );
      }
      // Primera carga: saltar sin animación para no ver el scroll desde arriba.
      _scrollToBottom(animate: !isFirst);
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeChatNotifier.setChat(null);
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
    if (_isOtherUserDeleted || _isBlockedByMe) return;
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
        ? l10n.chatBlockedCannotSend
        : l10n.genericError;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final bottom = _scrollController.position.minScrollExtent;
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
    if (_isOtherUserDeleted || _isBlockedByMe) return;
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
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final relationship = ref.watch(relationshipProvider(widget.otherUserId));
    final isBlockedByMe =
        relationship.asData?.value.status == RelationshipStatus.blocked;
    _isBlockedByMe = isBlockedByMe;
    final canPop = GoRouter.of(context).canPop();

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveChat();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: canPop ? null : BackButton(onPressed: _leaveChat),
          centerTitle: false,
          titleSpacing: 0,
          title: GestureDetector(
            onTap: _openOtherUserProfile,
            child: FutureBuilder<AppUser?>(
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
        body: Column(
          children: [
            // Lista de mensajes
            Expanded(child: _buildMessageList(colorScheme, l10n)),
            if (_isOtherUserDeleted)
              _buildDeletedAccountBar(colorScheme, l10n)
            else if (isBlockedByMe)
              _buildBlockedChatBar(colorScheme, l10n)
            else
              _buildInputBar(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(ColorScheme colorScheme, AppLocalizations l10n) {
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
            itemCount: _allMessages.length +
                (_deletedSince != null && !_hasMoreMessages ? 1 : 0),
            itemBuilder: (context, index) {
              // Banner de borrado: aparece encima de todos los mensajes (top de la lista invertida).
              if (_deletedSince != null &&
                  !_hasMoreMessages &&
                  index == _allMessages.length) {
                return _buildDeletedMessagesBanner(colorScheme, l10n);
              }

              final msg = _allMessages[_allMessages.length - 1 - index];
              final isMe = msg.senderId == _currentUid;

              if (msg.isTrack) {
                return TrackBubble(
                  message: msg,
                  isMe: isMe,
                  colorScheme: colorScheme,
                  currentUid: _currentUid,
                  chatId: widget.chatId,
                  chatService: ref.read(chatServiceProvider),
                  reactionsEnabled: !_isBlockedByMe,
                );
              }

              return MessageBubble(
                message: msg,
                isMe: isMe,
                colorScheme: colorScheme,
                currentUid: _currentUid,
                chatId: widget.chatId,
                chatService: ref.read(chatServiceProvider),
                reactionsEnabled: !_isBlockedByMe,
              );
            },
          ),
        ),
      ],
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

  Widget _buildDeletedMessagesBanner(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: colorScheme.onSurface.withAlpha(40))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              l10n.chatMessagesDeletedBanner,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ),
          Expanded(child: Divider(color: colorScheme.onSurface.withAlpha(40))),
        ],
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
}
