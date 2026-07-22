import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/utils/user_future_cache.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

/// Pantalla social: lista de conversaciones del usuario.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with AutomaticKeepAliveClientMixin, UserFutureCache {
  @override
  UserService get userService => ref.read(userServiceProvider);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowNotificationPrompt();
    });
  }

  Future<void> _maybeShowNotificationPrompt() async {
    final service = ref.read(notificationServiceProvider);
    if (service.hasShownPermissionDialog) return;
    await service.requestPermission();
  }

  /// UID of the authenticated user from the Riverpod provider.
  /// Returns empty string if session was lost (GoRouter redirects before this
  /// is reached in normal flow, but race conditions are possible).
  String get _currentUid =>
      ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  /// Obtiene el UID del otro participante del chat.
  String _otherUid(Chat chat) {
    return chat.participants.firstWhere(
      (uid) => uid != _currentUid,
      orElse: () => '',
    );
  }

  Future<void> _confirmDeleteChat(
    BuildContext context,
    String chatId,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.chatDeleteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.chatDeleteConfirm,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(chatServiceProvider).softDeleteChat(chatId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.genericError)));
      }
    }
  }

  /// Formatea la hora del último mensaje.
  String _formatTime(DateTime dateTime, AppLocalizations l10n) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return l10n.socialNow;
    if (diff.inHours < 1) return l10n.socialMinutes(diff.inMinutes);
    if (diff.inDays < 1) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return l10n.socialDays(diff.inDays);
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return ref
        .watch(chatsProvider)
        .when(
          loading: () => SkeletonShimmer(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: List.generate(6, (_) => const SkeletonChatListTile()),
            ),
          ),
          error: (error, _) {
            reportError(error, StackTrace.current);
            return Center(
              child: Text(
                l10n.socialErrorLoading,
                style: TextStyle(color: colorScheme.onSurface.withAlpha(150)),
              ),
            );
          },
          data: (chats) {
            if (chats.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.messageCircle,
                      size: 64,
                      color: colorScheme.onSurface.withAlpha(100),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.socialNoChats,
                      style: TextStyle(
                        color: colorScheme.onSurface.withAlpha(150),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.socialNoChatsHint,
                      style: TextStyle(
                        color: colorScheme.onSurface.withAlpha(100),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: chats.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 72,
                color: colorScheme.onSurface.withAlpha(30),
              ),
              itemBuilder: (context, index) {
                final chat = chats[index];
                final otherUid = _otherUid(chat);

                return FutureBuilder<AppUser?>(
                  future: getUserFuture(otherUid),
                  builder: (context, userSnap) {
                    final isLoading =
                        userSnap.connectionState == ConnectionState.waiting &&
                        !userSnap.hasData;
                    if (isLoading) {
                      return const SkeletonShimmer(
                        child: SkeletonChatListTile(),
                      );
                    }

                    final otherUser = userSnap.data;
                    final name = otherUser?.displayName ?? l10n.socialUser;
                    final photoUrl = otherUser?.photoUrl ?? '';

                  final unread = chat.unreadCounts[_currentUid] ?? 0;
                    return ListTile(
                      leading: UserCircleAvatar(
                        photoUrl: photoUrl,
                        name: name,
                        radius: 24,
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: unread > 0
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                      chat.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface.withAlpha(
                            unread > 0 ? 200 : 150,
                          ),
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                            Text(
                              _formatTime(chat.lastMessageTime, l10n),
                              style: TextStyle(
                                fontSize: 12,
                                color: unread > 0
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withAlpha(120),
                                fontWeight: unread > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          if (unread > 0) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onTap: () {
                        context.push(
                          Uri(
                            path: '/chat',
                            queryParameters: {
                              'chatId': chat.id,
                              'otherUserName': name,
                              'otherUserId': otherUid,
                            },
                          ).toString(),
                        );
                      },
                      onLongPress: () =>
                          _confirmDeleteChat(context, chat.id, l10n),
                    );
                  },
                );
              },
            );
          },
        );
  }
}
