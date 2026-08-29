import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/friend_request.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/utils/user_future_cache.dart';
import 'package:musi_link/widgets/friends/section_header.dart';
import 'package:musi_link/widgets/friends/empty_message.dart';
import 'package:musi_link/widgets/friends/request_tile.dart';
import 'package:musi_link/widgets/friends/friend_tile.dart';
import 'package:musi_link/widgets/remove_friend_dialog.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:go_router/go_router.dart';

/// Pantalla de amigos: solicitudes pendientes + lista de amigos.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with AutomaticKeepAliveClientMixin, UserFutureCache {
  List<String> _loadedFriendUids = const [];
  Future<List<AppUser>>? _friendProfilesFuture;
  final Map<String, String> _optimisticAcceptances = {};
  bool _reconciliationScheduled = false;

  @override
  UserService get userService => ref.read(userServiceProvider);

  @override
  bool get wantKeepAlive => true;

  Future<List<AppUser>> _getFriendProfiles(List<String> uids) {
    if (_friendProfilesFuture == null || !_sameUids(_loadedFriendUids, uids)) {
      _loadedFriendUids = List<String>.unmodifiable(uids);
      _friendProfilesFuture = userService.getUsersByIds(_loadedFriendUids);
    }
    return _friendProfilesFuture!;
  }

  bool _sameUids(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> _acceptRequest(String requestId, String otherUid) async {
    if (_optimisticAcceptances.containsKey(requestId)) return;

    setState(() {
      _optimisticAcceptances[requestId] = otherUid;
    });

    try {
      await ref.read(friendServiceProvider).acceptRequest(requestId, otherUid);
    } catch (_) {
      if (!mounted || _optimisticAcceptances[requestId] != otherUid) return;
      setState(() {
        _optimisticAcceptances.remove(requestId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.genericError)),
      );
    }
  }

  List<String> _withOptimisticFriends(List<String> friendUids) {
    final merged = friendUids.toList(growable: true);
    final seen = friendUids.toSet();
    for (final uid in _optimisticAcceptances.values) {
      if (seen.add(uid)) merged.add(uid);
    }
    return merged;
  }

  void _reconcileOptimisticAcceptances({
    required List<FriendRequest>? receivedRequests,
    required List<String>? friendUids,
  }) {
    if (_reconciliationScheduled ||
        receivedRequests == null ||
        friendUids == null ||
        _optimisticAcceptances.isEmpty) {
      return;
    }

    final pendingRequestIds = receivedRequests
        .map((request) => request.id)
        .toSet();
    final confirmedFriendUids = friendUids.toSet();
    final confirmedRequestIds = _optimisticAcceptances.entries
        .where(
          (entry) =>
              confirmedFriendUids.contains(entry.value) &&
              !pendingRequestIds.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    if (confirmedRequestIds.isEmpty) return;

    _reconciliationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconciliationScheduled = false;
      if (!mounted) return;
      final hasPendingConfirmation = confirmedRequestIds.any(
        _optimisticAcceptances.containsKey,
      );
      if (!hasPendingConfirmation) return;
      setState(() {
        for (final requestId in confirmedRequestIds) {
          _optimisticAcceptances.remove(requestId);
        }
      });
    });
  }

  Future<void> _showRemoveFriendDialog(String uid, String? name) async {
    final confirmed = await showRemoveFriendDialog(context);
    if (confirmed == true) {
      invalidateUserFuture(uid);
      await ref.read(friendServiceProvider).removeFriend(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final receivedAsync = ref.watch(receivedRequestsProvider);
    final sentAsync = ref.watch(sentRequestsProvider);
    final friendsAsync = ref.watch(friendsStreamProvider);
    _reconcileOptimisticAcceptances(
      receivedRequests: receivedAsync.asData?.value,
      friendUids: friendsAsync.asData?.value,
    );

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ─── Solicitudes recibidas ───────────────────
          SectionHeader(title: l10n.friendsReceivedRequests),
          receivedAsync.when(
            loading: () => SkeletonShimmer(
              child: Column(
                children: List.generate(2, (_) => const SkeletonRequestTile()),
              ),
            ),
            error: (_, _) => Center(child: Text(l10n.genericError)),
            data: (requests) {
              final visibleRequests = requests
                  .where(
                    (request) =>
                        !_optimisticAcceptances.containsKey(request.id),
                  )
                  .toList(growable: false);
              if (visibleRequests.isEmpty) {
                return EmptyMessage(text: l10n.friendsNoRequests);
              }
              return Column(
                children: visibleRequests.map((request) {
                  return RequestTile(
                    uid: request.senderId,
                    getUserFuture: getUserFuture,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            LucideIcons.circleCheck,
                            color: colorScheme.primary,
                          ),
                          tooltip: l10n.friendsAccept,
                          onPressed: () =>
                              _acceptRequest(request.id, request.senderId),
                        ),
                        IconButton(
                          icon: Icon(
                            LucideIcons.circleX,
                            color: colorScheme.error,
                          ),
                          tooltip: l10n.friendsReject,
                          onPressed: () => ref
                              .read(friendServiceProvider)
                              .rejectRequest(request.id),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 8),

          // ─── Solicitudes enviadas ────────────────────
          SectionHeader(title: l10n.friendsSentRequests),
          sentAsync.when(
            loading: () => SkeletonShimmer(
              child: Column(
                children: List.generate(2, (_) => const SkeletonRequestTile()),
              ),
            ),
            error: (_, _) => Center(child: Text(l10n.genericError)),
            data: (requests) {
              if (requests.isEmpty) {
                return EmptyMessage(text: l10n.friendsNoRequests);
              }
              return Column(
                children: requests.map((request) {
                  return RequestTile(
                    uid: request.receiverId,
                    getUserFuture: getUserFuture,
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(friendServiceProvider)
                          .cancelRequest(request.id),
                      child: Text(l10n.friendsCancel),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 8),

          // ─── Lista de amigos ─────────────────────────
          SectionHeader(title: l10n.friendsMyFriends),
          friendsAsync.when(
            loading: () => SkeletonShimmer(
              child: Column(
                children: List.generate(3, (_) => const SkeletonListTile()),
              ),
            ),
            error: (_, _) => Center(child: Text(l10n.genericError)),
            data: (friendUids) {
              final visibleFriendUids = _withOptimisticFriends(friendUids);
              if (visibleFriendUids.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmptyMessage(text: l10n.friendsNoFriends),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        l10n.friendsNoFriendsHint,
                        style: TextStyle(
                          color: colorScheme.onSurface.withAlpha(100),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return FutureBuilder<List<AppUser>>(
                future: _getFriendProfiles(visibleFriendUids),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return SkeletonShimmer(
                      child: Column(
                        children: List.generate(
                          visibleFriendUids.length.clamp(1, 3),
                          (_) => const SkeletonListTile(),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(l10n.genericError));
                  }

                  final usersById = {
                    for (final user in snapshot.data ?? const <AppUser>[])
                      user.uid: user,
                  };
                  return Column(
                    children: visibleFriendUids.map((uid) {
                      final user = usersById[uid];
                      return FriendTile(
                        user: user,
                        onTap: (selectedUser) {
                          if (selectedUser != null) {
                            // Invalida el caché para obtener los datos más recientes (ej. Now Playing)
                            invalidateUserFuture(selectedUser.uid);
                            context.push(
                              userProfileLocation(selectedUser.uid),
                              extra: selectedUser,
                            );
                          }
                        },
                        onLongPress: (selectedUser) => _showRemoveFriendDialog(
                          uid,
                          selectedUser?.displayName,
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        onPressed: () => context.push('/search'),
        child: const Icon(LucideIcons.userSearch),
      ),
    );
  }
}
