import 'package:material_ui/material_ui.dart';

import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

class FriendshipButtons extends StatefulWidget {
  final AsyncValue<RelationshipResult> value;
  final VoidCallback onStartChat;
  final Future<void> Function() onSendRequest;
  final void Function(String requestId) onAcceptRequest;
  final void Function(String requestId) onRejectRequest;
  final void Function(String requestId) onCancelRequest;
  final VoidCallback onRemoveFriend;
  final VoidCallback onUnblock;

  const FriendshipButtons({
    super.key,
    required this.value,
    required this.onStartChat,
    required this.onSendRequest,
    required this.onAcceptRequest,
    required this.onRejectRequest,
    required this.onCancelRequest,
    required this.onRemoveFriend,
    required this.onUnblock,
  });

  @override
  State<FriendshipButtons> createState() => _FriendshipButtonsState();
}

class _FriendshipButtonsState extends State<FriendshipButtons> {
  /// Estado optimista local. Cuando no es null, se usa en lugar del valor real
  /// para evitar el spinner mientras Firestore confirma la operación.
  RelationshipStatus? _optimisticStatus;

  Future<void> _handleSendRequest() async {
    setState(() => _optimisticStatus = RelationshipStatus.requestSent);
    try {
      await widget.onSendRequest();
    } catch (_) {
      if (mounted) setState(() => _optimisticStatus = null);
    }
  }

  void _handleCancelRequest(String requestId) {
    setState(() => _optimisticStatus = RelationshipStatus.none);
    widget.onCancelRequest(requestId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final relationship = widget.value.asData?.value;
    final isLoading = widget.value.isLoading;
    final hasError = widget.value.hasError;

    if (isLoading && _optimisticStatus == null) {
      return const SkeletonShimmer(child: SkeletonFriendshipButtons());
    }

    if (hasError && relationship == null) return const SizedBox.shrink();

    final shouldClearOptimisticStatus =
        !isLoading &&
        _optimisticStatus != null &&
        relationship != null &&
        (relationship.status == _optimisticStatus ||
            (_optimisticStatus == RelationshipStatus.requestSent &&
                relationship.status == RelationshipStatus.friends));

    if (shouldClearOptimisticStatus) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _optimisticStatus = null),
      );
    }

    final status =
        _optimisticStatus ?? relationship?.status ?? RelationshipStatus.none;
    final requestId = relationship?.requestId;

    switch (status) {
      case RelationshipStatus.friends:
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.onStartChat,
                icon: const Icon(LucideIcons.messageCircle),
                label: Text(l10n.profileStartChat),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRemoveFriend,
                icon: Icon(LucideIcons.userMinus, color: cs.error),
                label: Text(
                  l10n.friendsRemove,
                  style: TextStyle(color: cs.error),
                ),
              ),
            ),
          ],
        );

      case RelationshipStatus.requestSent:
        return OutlinedButton.icon(
          onPressed: _optimisticStatus != null
              ? () {}
              : requestId != null
              ? () => _handleCancelRequest(requestId)
              : null,
          icon: const Icon(LucideIcons.hourglass),
          label: Text(l10n.friendsRequestSent),
        );

      case RelationshipStatus.requestReceived:
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: requestId != null
                    ? () => widget.onAcceptRequest(requestId)
                    : null,
                icon: const Icon(LucideIcons.check),
                label: Text(l10n.friendsAccept),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: requestId != null
                    ? () => widget.onRejectRequest(requestId)
                    : null,
                icon: const Icon(LucideIcons.x),
                label: Text(l10n.friendsReject),
              ),
            ),
          ],
        );

      case RelationshipStatus.none:
        return FilledButton.icon(
          onPressed: () => unawaited(_handleSendRequest()),
          icon: const Icon(LucideIcons.userPlus),
          label: Text(l10n.profileAddFriend),
        );

      case RelationshipStatus.blocked:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onUnblock,
            icon: Icon(LucideIcons.userCheck, color: cs.error),
            label: Text(
              l10n.blockUserUnblock,
              style: TextStyle(color: cs.error),
            ),
          ),
        );
    }
  }
}
