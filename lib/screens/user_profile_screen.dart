import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/widgets/profile/compatibility_card.dart';
import 'package:musi_link/widgets/profile/friendship_buttons.dart';
import 'package:musi_link/widgets/profile/music_taste_section.dart';
import 'package:musi_link/widgets/profile/profile_daily_song_card.dart';
import 'package:musi_link/widgets/profile/profile_header.dart';
import 'package:musi_link/widgets/remove_friend_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ProfileMenuAction { block, unblock }

class UserProfileScreen extends ConsumerStatefulWidget {
  final AppUser user;
  final DiscoveryResult? initialCompatibility;
  final bool fromChat;

  const UserProfileScreen({
    super.key,
    required this.user,
    this.initialCompatibility,
    this.fromChat = false,
  });

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  /// UID of the authenticated user from the Riverpod provider.
  /// Returns empty string on session loss — _isOwnProfile then evaluates to
  /// false (safe: shows the other-user view, actions are gated by GoRouter).
  String get _currentUid =>
      ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
  bool get _isOwnProfile =>
      widget.user.uid == _currentUid && _currentUid.isNotEmpty;

  Future<void> _startChat() async {
    if (widget.user.isDeleted) return;
    if (widget.fromChat && context.canPop()) {
      context.pop();
      return;
    }
    final chat = await ref
        .read(chatServiceProvider)
        .getOrCreateChat(widget.user.uid);
    if (!mounted) return;
    unawaited(
      context.push(
        Uri(
          path: '/chat',
          queryParameters: {
            'chatId': chat.id,
            'otherUserName': widget.user.displayName,
            'otherUserId': widget.user.uid,
          },
        ).toString(),
      ),
    );
  }

  Future<void> _sendRequest() async {
    if (widget.user.isDeleted) return;
    try {
      await ref.read(friendServiceProvider).sendRequest(widget.user.uid);
      if (!mounted) return;
      ref.invalidate(relationshipProvider(widget.user.uid));
    } on FirebaseException catch (e) {
      if (mounted) _showWriteError(e);
      rethrow;
    } catch (_) {
      if (mounted) _showWriteError(null);
      rethrow;
    }
  }

  void _showWriteError(FirebaseException? error) {
    final l10n = AppLocalizations.of(context)!;
    final message = error?.code == 'permission-denied'
        ? l10n.authErrorTooManyRequests
        : l10n.genericError;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _acceptRequest(String requestId) async {
    await ref
        .read(friendServiceProvider)
        .acceptRequest(requestId, widget.user.uid);
    if (!mounted) return;
    ref.invalidate(relationshipProvider(widget.user.uid));
  }

  Future<void> _rejectRequest(String requestId) async {
    await ref.read(friendServiceProvider).rejectRequest(requestId);
    if (!mounted) return;
    ref.invalidate(relationshipProvider(widget.user.uid));
  }

  Future<void> _cancelRequest(String requestId) async {
    await ref.read(friendServiceProvider).cancelRequest(requestId);
    if (!mounted) return;
    ref.invalidate(relationshipProvider(widget.user.uid));
  }

  Future<void> _blockUser() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.blockUserBlockConfirmTitle(widget.user.displayName)),
        content: Text(l10n.blockUserBlockConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.friendsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.blockUserBlockConfirm,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(friendServiceProvider).blockUser(widget.user.uid);
      ref.read(musicProfileServiceProvider).clearCache();
      if (!mounted) return;
      ref.invalidate(relationshipProvider(widget.user.uid));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.blockUserBlockedSnackbar(widget.user.displayName),
          ),
        ),
      );
    } catch (_) {
      if (mounted) _showWriteError(null);
    }
  }

  Future<void> _unblockUser() async {
    try {
      await ref.read(friendServiceProvider).unblockUser(widget.user.uid);
      if (!mounted) return;
      ref.invalidate(relationshipProvider(widget.user.uid));
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.blockUserUnblockedSnackbar(widget.user.displayName),
          ),
        ),
      );
    } catch (_) {
      if (mounted) _showWriteError(null);
    }
  }

  Future<void> _removeFriend() async {
    final confirmed = await showRemoveFriendDialog(context);
    if (confirmed == true) {
      await ref.read(friendServiceProvider).removeFriend(widget.user.uid);
      if (!mounted) return;
      ref.invalidate(relationshipProvider(widget.user.uid));
    }
  }

  Future<void> _openSpotifyUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user =
        ref.watch(userStreamProvider(widget.user.uid)).asData?.value ??
        widget.user;
    final hasMusicalData =
        user.topArtists.isNotEmpty || user.topGenres.isNotEmpty;
    final isDeletedProfile = user.isDeleted;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          if (!_isOwnProfile && !isDeletedProfile)
            Consumer(
              builder: (ctx, ref, _) {
                final isBlocked =
                    ref
                        .watch(relationshipProvider(widget.user.uid))
                        .asData
                        ?.value
                        .status ==
                    RelationshipStatus.blocked;
                return PopupMenuButton<_ProfileMenuAction>(
                  icon: const Icon(LucideIcons.ellipsisVertical),
                  onSelected: (action) {
                    if (action == _ProfileMenuAction.block) _blockUser();
                    if (action == _ProfileMenuAction.unblock) _unblockUser();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: isBlocked
                          ? _ProfileMenuAction.unblock
                          : _ProfileMenuAction.block,
                      child: Text(
                        isBlocked
                            ? l10n.blockUserUnblock
                            : l10n.blockUserBlock,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 24,
          bottom: 24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            ProfileHeader(user: user),
            const SizedBox(height: 20),

            if (user.dailySong != null)
              ProfileDailySongCard(
                song: user.dailySong!,
                onTap: user.dailySong!.spotifyUrl.isNotEmpty
                    ? () => _openSpotifyUrl(user.dailySong!.spotifyUrl)
                    : null,
              ),

            const SizedBox(height: 4),

            if (!_isOwnProfile && !isDeletedProfile)
              Builder(
                builder: (context) {
                  final initialCompatibility = widget.initialCompatibility;
                  final compatibilityValue =
                      initialCompatibility != null &&
                          initialCompatibility.user.uid == user.uid
                      ? AsyncValue<DiscoveryResult>.data(initialCompatibility)
                      : ref.watch(compatibilityProvider(user));
                  final relationshipValue = ref.watch(
                    relationshipProvider(widget.user.uid),
                  );

                  return Column(
                    children: [
                      CompatibilityCard(value: compatibilityValue),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: FriendshipButtons(
                          value: relationshipValue,
                          onStartChat: _startChat,
                          onSendRequest: _sendRequest,
                          onAcceptRequest: _acceptRequest,
                          onRejectRequest: _rejectRequest,
                          onCancelRequest: _cancelRequest,
                          onRemoveFriend: _removeFriend,
                          onUnblock: _unblockUser,
                        ),
                      ),
                    ],
                  );
                },
              ),

            const SizedBox(height: 24),

            if (!hasMusicalData)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.profileNoData,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            MusicTasteSection(user: user),
          ],
        ),
      ),
    );
  }
}
