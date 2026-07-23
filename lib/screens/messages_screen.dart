import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/utils/user_future_cache.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/pwa_environment.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

/// Pantalla social: lista de conversaciones del usuario.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with AutomaticKeepAliveClientMixin, UserFutureCache {
  PushPermissionState? _webPushState;
  bool _webPushRequiresInstallation = false;
  bool _requestingWebPush = false;

  @override
  UserService get userService => ref.read(userServiceProvider);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _configureNotifications();
    });
  }

  Future<void> _configureNotifications() async {
    final service = ref.read(notificationServiceProvider);
    if (kIsWeb) {
      if (isIosWebPlatform && !isRunningAsInstalledPwa) {
        if (mounted) setState(() => _webPushRequiresInstallation = true);
        return;
      }
      final state = await service.getPermissionState();
      if (mounted) setState(() => _webPushState = state);
      return;
    }
    if (service.hasShownPermissionDialog) return;
    await service.requestPermission();
  }

  Future<void> _requestWebPushPermission() async {
    if (_requestingWebPush) return;
    setState(() => _requestingWebPush = true);
    try {
      final service = ref.read(notificationServiceProvider);
      await service.requestPermission();
      final state = await service.getPermissionState();
      if (mounted) setState(() => _webPushState = state);
    } catch (error, stack) {
      await reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.pushNotificationsError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingWebPush = false);
    }
  }

  bool get _showWebPushCard =>
      kIsWeb &&
      (_webPushRequiresInstallation ||
          (_webPushState != null &&
              _webPushState != PushPermissionState.enabled));

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
            final chatList = chats.isEmpty
                ? Center(
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
                  )
                : ListView.separated(
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
                              userSnap.connectionState ==
                                  ConnectionState.waiting &&
                              !userSnap.hasData;
                          if (isLoading) {
                            return const SkeletonShimmer(
                              child: SkeletonChatListTile(),
                            );
                          }

                          final otherUser = userSnap.data;
                          final name =
                              otherUser?.displayName ?? l10n.socialUser;
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

            return Column(
              children: [
                if (_showWebPushCard)
                  _WebPushCard(
                    state: _webPushState,
                    requiresInstallation: _webPushRequiresInstallation,
                    requesting: _requestingWebPush,
                    onEnable: _requestWebPushPermission,
                  ),
                Expanded(child: chatList),
              ],
            );
          },
        );
  }
}

class _WebPushCard extends StatelessWidget {
  const _WebPushCard({
    required this.state,
    required this.requiresInstallation,
    required this.requesting,
    required this.onEnable,
  });

  final PushPermissionState? state;
  final bool requiresInstallation;
  final bool requesting;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final body = requiresInstallation
        ? l10n.pushNotificationsInstallBody
        : switch (state) {
            PushPermissionState.denied => l10n.pushNotificationsBlockedBody,
            PushPermissionState.unsupported =>
              l10n.pushNotificationsUnsupportedBody,
            _ => l10n.pushNotificationsBody,
          };
    final canEnable =
        !requiresInstallation && state == PushPermissionState.notDetermined;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.bellRing, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pushNotificationsTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                  if (canEnable) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: requesting ? null : onEnable,
                      icon: requesting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.bell, size: 18),
                      label: Text(l10n.pushNotificationsEnable),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
