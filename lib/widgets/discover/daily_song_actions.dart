import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/daily_song_reply_provider.dart';
import 'package:musi_link/widgets/discover/daily_song_reply_sheet.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:musi_link/services/daily_song_interaction_service.dart';

/// Whether [uid] may like or reply to [owner]'s current song of the day.
bool canInteractWithDailySong(
  AppUser owner, {
  required String? uid,
  required List<String> friends,
  required List<String> blocked,
}) =>
    uid != null &&
    uid != owner.uid &&
    owner.dailySong != null &&
    owner.dailySongUpdatedAt != null &&
    friends.contains(owner.uid) &&
    !blocked.contains(owner.uid);

/// Opens the reply sheet for [owner]'s song of the day and sends the reply to
/// the private chat, offering a retry when it fails.
Future<void> replyToDailySong(
  BuildContext context,
  WidgetRef ref,
  AppUser owner, {
  FailedDailySongReply? draft,
}) async {
  final song = owner.dailySong;
  if (song == null) return;
  final notifier = ref.read(dailySongReplyProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  if (draft != null) messenger.hideCurrentSnackBar();
  final auth = ref.read(firebaseAuthProvider);
  final senderId = auth.currentUser?.uid;
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
        action: context.mounted
            ? SnackBarAction(
                label: l10n.dailySongRetry,
                onPressed: () {
                  if (context.mounted) {
                    replyToDailySong(context, ref, owner, draft: failure);
                  }
                },
              )
            : null,
      ),
    );
  }
}

/// Heart toggle that pops when liked instead of showing an ink ripple.
class _DailySongLikeButton extends StatefulWidget {
  const _DailySongLikeButton({
    required this.liked,
    required this.tooltip,
    required this.onPressed,
  });

  final bool liked;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_DailySongLikeButton> createState() => _DailySongLikeButtonState();
}

class _DailySongLikeButtonState extends State<_DailySongLikeButton>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppTokens.durationSlow,
  );
  late final _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.8,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 20,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.8,
        end: 1.25,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.25,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 40,
    ),
  ]).animate(_controller);
  late final _dip = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.85,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.85,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(_DailySongLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: widget.onPressed,
      isSelected: widget.liked,
      tooltip: widget.tooltip,
      style: IconButton.styleFrom(
        splashFactory: NoSplash.splashFactory,
        overlayColor: Colors.transparent,
      ),
      icon: ScaleTransition(
        scale: widget.liked ? _pop : _dip,
        child: Icon(
          widget.liked ? Icons.favorite : Icons.favorite_border,
          color: widget.liked
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Lists who liked the signed-in user's own [publication].
Future<void> showDailySongLikesSheet(
  BuildContext context,
  DailySongPublication publication,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (_) => _DailySongLikesSheet(publication: publication),
);

class DailySongActions extends ConsumerStatefulWidget {
  const DailySongActions({super.key, required this.owner});

  final AppUser owner;

  @override
  ConsumerState<DailySongActions> createState() => _DailySongActionsState();
}

class _DailySongActionsState extends ConsumerState<DailySongActions> {
  bool _saving = false;

  /// Like state shown from the tap until the stream confirms it, so the
  /// button reacts immediately even when the write needs a server round trip.
  bool? _optimisticLiked;

  @override
  void didUpdateWidget(DailySongActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner.uid != widget.owner.uid ||
        oldWidget.owner.dailySongUpdatedAt != widget.owner.dailySongUpdatedAt) {
      _optimisticLiked = null;
    }
  }

  Future<void> _setLiked(DailySongPublication publication, bool liked) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _optimisticLiked = liked;
    });
    try {
      await ref
          .read(dailySongInteractionServiceProvider)
          .setLiked(publication, liked);
    } catch (_) {
      if (mounted) {
        setState(() => _optimisticLiked = null);
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
            !canInteractWithDailySong(
              owner,
              uid: uid,
              friends: friends,
              blocked: blocked,
            ))) {
      return const SizedBox.shrink();
    }
    final publication = (
      ownerId: owner.uid,
      publishedAt: owner.dailySongUpdatedAt!,
    );
    final l10n = AppLocalizations.of(context)!;
    if (own) {
      return TextButton.icon(
        onPressed: () => showDailySongLikesSheet(context, publication),
        icon: const Icon(Icons.favorite, size: 18),
        label: Text(l10n.dailySongLikesTitle),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    ref.listen(dailySongMyLikeProvider(publication), (_, next) {
      if (_optimisticLiked != null && next.asData?.value == _optimisticLiked) {
        setState(() => _optimisticLiked = null);
      }
    });
    final likes = ref.watch(dailySongMyLikeProvider(publication));
    final liked = _optimisticLiked ?? likes.asData?.value ?? false;
    final failedReplies = ref
        .watch(dailySongReplyProvider)
        .where((reply) => reply.matches(owner))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                child: Material(
                  color: colorScheme.surfaceContainer,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => replyToDailySong(context, ref, owner),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceLG,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.reply,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppTokens.spaceSM),
                          Expanded(
                            child: Text(
                              l10n.dailySongReply,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceXS),
            if (likes.hasError)
              IconButton(
                onPressed: () =>
                    ref.invalidate(dailySongMyLikeProvider(publication)),
                tooltip: l10n.dailySongRetry,
                icon: const Icon(Icons.refresh),
              )
            else if (likes.isLoading)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              _DailySongLikeButton(
                liked: liked,
                tooltip: liked ? l10n.dailySongUnlike : l10n.dailySongLike,
                onPressed: () => _setLiked(publication, !liked),
              ),
          ],
        ),
        for (final failed in failedReplies)
          TextButton.icon(
            onPressed: () =>
                replyToDailySong(context, ref, owner, draft: failed),
            icon: const Icon(Icons.error_outline),
            label: Text(l10n.dailySongRetry),
          ),
      ],
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
