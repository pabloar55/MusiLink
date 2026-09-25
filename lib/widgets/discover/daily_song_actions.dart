import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/daily_song_reply_provider.dart';
import 'package:musi_link/widgets/discover/daily_song_reply_sheet.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:musi_link/services/daily_song_interaction_service.dart';

class DailySongActions extends ConsumerStatefulWidget {
  const DailySongActions({super.key, required this.owner});

  final AppUser owner;

  @override
  ConsumerState<DailySongActions> createState() => _DailySongActionsState();
}

class _DailySongActionsState extends ConsumerState<DailySongActions> {
  bool _saving = false;

  Future<void> _setLiked(DailySongPublication publication, bool liked) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(dailySongInteractionServiceProvider)
          .setLiked(publication, liked);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.dailySongInteractionError,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openReply(AppUser owner, {FailedDailySongReply? draft}) async {
    final song = owner.dailySong;
    if (song == null) return;
    final notifier = ref.read(dailySongReplyProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (draft != null) messenger.hideCurrentSnackBar();
    final senderId = ref.read(firebaseAuthProvider).currentUser?.uid;
    final auth = ref.read(firebaseAuthProvider);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DailySongReplySheet(
        owner: owner,
        song: song,
        initialText: draft?.text ?? '',
      ),
    );
    if (text == null || text.isEmpty || auth.currentUser?.uid != senderId) {
      return;
    }
    final failure = await notifier.send(owner, text, retryOf: draft);
    if (failure != null && messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.dailySongInteractionError),
          action: mounted
              ? SnackBarAction(
                  label: l10n.dailySongRetry,
                  onPressed: () {
                    if (mounted) _openReply(owner, draft: failure);
                  },
                )
              : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.owner;
    final uid =
        ref.watch(authStateProvider).asData?.value?.uid ??
        ref.watch(firebaseAuthProvider).currentUser?.uid;
    final own = uid == owner.uid;
    final friends =
        ref.watch(friendsStreamProvider).asData?.value ?? const <String>[];
    final blocked =
        ref.watch(blockedUsersProvider).asData?.value ?? const <String>[];
    if (uid == null ||
        owner.dailySong == null ||
        owner.dailySongUpdatedAt == null ||
        (!own &&
            (!friends.contains(owner.uid) || blocked.contains(owner.uid)))) {
      return const SizedBox.shrink();
    }
    final publication = (
      ownerId: owner.uid,
      publishedAt: owner.dailySongUpdatedAt!,
    );
    if (own) return _DailySongPrivateLikes(publication: publication);
    final likes = ref.watch(dailySongMyLikeProvider(publication));
    final l10n = AppLocalizations.of(context)!;
    final liked = likes.asData?.value ?? false;
    final failedReplies = ref
        .watch(dailySongReplyProvider)
        .where((reply) => reply.matches(owner))
        .toList();
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (likes.hasError)
          TextButton.icon(
            onPressed: () =>
                ref.invalidate(dailySongMyLikeProvider(publication)),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.dailySongRetry),
          )
        else if (likes.isLoading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            onPressed: _saving ? null : () => _setLiked(publication, !liked),
            isSelected: liked,
            iconSize: 28,
            tooltip: liked ? l10n.dailySongUnlike : l10n.dailySongLike,
            color: Theme.of(context).colorScheme.primary,
            icon: const Icon(Icons.favorite_border),
            selectedIcon: const Icon(Icons.favorite),
          ),
        if (!own)
          TextButton.icon(
            onPressed: () => _openReply(owner),
            icon: const Icon(Icons.reply, size: 20),
            label: Text(
              l10n.dailySongReply,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        for (final failed in failedReplies)
          TextButton.icon(
            onPressed: () => _openReply(owner, draft: failed),
            icon: const Icon(Icons.error_outline),
            label: Text(l10n.dailySongRetry),
          ),
      ],
    );
  }
}

class _DailySongPrivateLikes extends ConsumerWidget {
  const _DailySongPrivateLikes({required this.publication});
  final DailySongPublication publication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likes = ref.watch(dailySongLikesProvider(publication));
    final l10n = AppLocalizations.of(context)!;
    return likes.when(
      loading: () => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => TextButton.icon(
        onPressed: () => ref.invalidate(dailySongLikesProvider(publication)),
        icon: const Icon(Icons.refresh),
        label: Text(l10n.dailySongRetry),
      ),
      data: (uids) => TextButton.icon(
        icon: const Icon(Icons.favorite, size: 28),
        label: Text('${uids.length} · ${l10n.dailySongLikesTitle}'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => _DailySongLikesSheet(publication: publication),
        ),
      ),
    );
  }
}

class _DailySongLikesSheet extends ConsumerWidget {
  const _DailySongLikesSheet({required this.publication});
  final DailySongPublication publication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final likes = ref.watch(dailySongLikesProvider(publication));
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.dailySongLikesTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: likes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(dailySongLikesProvider(publication)),
                  child: Text(l10n.dailySongRetry),
                ),
              ),
              data: (uids) {
                if (uids.isEmpty) {
                  return Center(child: Text(l10n.dailySongNoLikes));
                }
                final sorted = uids.toList()..sort();
                return ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (_, index) =>
                      _DailySongLikerTile(uid: sorted[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DailySongLikerTile extends ConsumerWidget {
  const _DailySongLikerTile({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStreamProvider(uid));
    final l10n = AppLocalizations.of(context)!;
    return user.when(
      loading: () => const ListTile(
        leading: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => ListTile(
        title: Text(l10n.dailySongLoadError),
        trailing: IconButton(
          tooltip: l10n.dailySongRetry,
          onPressed: () => ref.invalidate(userStreamProvider(uid)),
          icon: const Icon(Icons.refresh),
        ),
      ),
      data: (profile) => profile == null
          ? const SizedBox.shrink()
          : ListTile(
              leading: UserCircleAvatar(
                photoUrl: profile.photoUrl,
                name: profile.displayName,
                radius: 20,
              ),
              title: Text(profile.displayName),
              subtitle: profile.username.isEmpty
                  ? null
                  : Text('@${profile.username}'),
            ),
    );
  }
}
