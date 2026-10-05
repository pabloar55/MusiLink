import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/utils/spotify_url.dart';
import 'package:musi_link/widgets/discover/daily_song_card.dart';
import 'package:musi_link/widgets/discover/daily_song_actions.dart';
import 'package:musi_link/widgets/discover/daily_song_menu_sheet.dart';
import 'package:musi_link/widgets/discover/daily_song_search_sheet.dart';
import 'package:musi_link/widgets/discover/friend_daily_song_card.dart';
import 'package:musi_link/widgets/discover/invite_friends_card.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class DailySongTab extends ConsumerStatefulWidget {
  const DailySongTab({super.key});

  @override
  ConsumerState<DailySongTab> createState() => _DailySongTabState();
}

class _DailySongTabState extends ConsumerState<DailySongTab>
    with AutomaticKeepAliveClientMixin<DailySongTab> {
  Timer? _expiryTimer;
  DateTime? _scheduledExpiry;

  /// UID of the authenticated user from the Riverpod provider.
  /// Returns empty string on session loss; actions stop until routing completes.
  String get _currentUid =>
      ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  @override
  bool get wantKeepAlive => true;

  Future<void> _chooseDailySong() async {
    final uid = _currentUid;
    if (uid.isEmpty) {
      return; // Session lost — skip silently, GoRouter redirects.
    }
    final track = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const DailySongSearchSheet(),
    );
    if (track == null || !mounted) return;
    await _saveDailySong(uid, track);
  }

  Future<void> _saveDailySong(String uid, Track track) async {
    final saved = await ref
        .read(dailySongSaveProvider.notifier)
        .save(uid, track);
    if (!saved && mounted) _showSaveError();
  }

  Future<void> _retrySave() async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    final saved = await ref.read(dailySongSaveProvider.notifier).retry(uid);
    if (!saved && mounted) _showSaveError();
  }

  void _showSaveError() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.dailySongSaveError)));
  }

  Future<void> _refreshData() async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    try {
      final friendIds = await ref
          .read(friendServiceProvider)
          .getFriends(serverOnly: true);
      await Future.wait([
        ref
            .read(userServiceProvider)
            .getUser(uid, bypassCache: true, serverOnly: true),
        ref.read(userServiceProvider).getUsersByIdsFromServer(friendIds),
      ]);
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.dailySongRefreshError)));
    }
  }

  Future<void> _retryLoad() async {
    ref.invalidate(currentUserProvider);
    ref.invalidate(friendsStreamProvider);
    ref.invalidate(friendProfilesStreamProvider);
    await _refreshData();
  }

  void _scheduleExpiryRefresh(AppUser? currentUser, List<AppUser> friends) {
    final now = DateTime.now();
    final expirations = <DateTime>[
      if (currentUser?.dailySong != null &&
          currentUser?.dailySongUpdatedAt != null)
        currentUser!.dailySongUpdatedAt!.add(AppUser.dailySongLifetime),
      for (final friend in friends)
        if (friend.dailySong != null && friend.dailySongUpdatedAt != null)
          friend.dailySongUpdatedAt!.add(AppUser.dailySongLifetime),
    ].where((expiry) => expiry.isAfter(now)).toList();
    expirations.sort();
    final nextExpiry = expirations.firstOrNull;
    if (_scheduledExpiry == nextExpiry) return;

    _expiryTimer?.cancel();
    _scheduledExpiry = nextExpiry;
    if (nextExpiry == null) return;

    _expiryTimer = Timer(nextExpiry.difference(now), () {
      if (!mounted) return;
      _scheduledExpiry = null;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _openSpotify(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openOwnSongMenu(AppUser user) {
    final song = user.dailySong;
    if (song == null) return;
    final l10n = AppLocalizations.of(context)!;
    final spotifyUri = parseSpotifyTrackUri(song.spotifyUrl);
    final publishedAt = user.dailySongUpdatedAt;
    showDailySongMenu(
      context,
      song: song,
      items: [
        if (spotifyUri != null)
          (
            icon: LucideIcons.externalLink,
            label: l10n.dailySongOpenInSpotify,
            onTap: () => _openSpotify(spotifyUri),
          ),
        if (publishedAt != null)
          (
            icon: LucideIcons.heart,
            label: l10n.dailySongLikesTitle,
            onTap: () {
              if (!mounted) return;
              showDailySongLikesSheet(context, (
                ownerId: user.uid,
                publishedAt: publishedAt,
              ));
            },
          ),
        (
          icon: LucideIcons.pencil,
          label: l10n.dailySongChoose,
          onTap: () {
            if (mounted && !ref.read(dailySongSaveProvider).isSaving) {
              _chooseDailySong();
            }
          },
        ),
      ],
    );
  }

  void _openFriendSongMenu(AppUser friend) {
    final song = friend.dailySong;
    if (song == null) return;
    final l10n = AppLocalizations.of(context)!;
    final spotifyUri = parseSpotifyTrackUri(song.spotifyUrl);
    final canReply = canInteractWithDailySong(
      friend,
      uid: _currentUid.isEmpty ? null : _currentUid,
      friends: ref.read(friendsStreamProvider).asData?.value ?? const [],
      blocked: ref.read(blockedUsersProvider).asData?.value ?? const [],
    );
    showDailySongMenu(
      context,
      song: song,
      items: [
        if (spotifyUri != null)
          (
            icon: LucideIcons.externalLink,
            label: l10n.dailySongOpenInSpotify,
            onTap: () => _openSpotify(spotifyUri),
          ),
        if (canReply)
          (
            icon: LucideIcons.reply,
            label: l10n.dailySongReply,
            onTap: () {
              if (mounted) replyToDailySong(context, ref, friend);
            },
          ),
        (
          icon: LucideIcons.user,
          label: l10n.dailySongViewProfile,
          onTap: () => _openProfile(friend),
        ),
      ],
    );
  }

  void _openProfile(AppUser friend) {
    if (!mounted) return;
    context.push(userProfileLocation(friend.uid), extra: friend);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final currentUserAsync = ref.watch(currentUserProvider);
    final friendIdsAsync = ref.watch(friendsStreamProvider);
    final friendProfilesAsync = ref.watch(friendProfilesStreamProvider);
    final saveState = ref.watch(dailySongSaveProvider);

    final currentUser = currentUserAsync.asData?.value;
    final friendIds = friendIdsAsync.asData?.value;
    final friends = friendProfilesAsync.asData?.value;
    final loadError =
        currentUserAsync.asError?.error ??
        friendIdsAsync.asError?.error ??
        friendProfilesAsync.asError?.error;

    if (loadError == null &&
        (currentUserAsync.asData == null ||
            friendIds == null ||
            friends == null)) {
      return const SkeletonShimmer(child: SkeletonDailySongTab());
    }

    if (loadError != null &&
        currentUserAsync.asData == null &&
        friendIds == null &&
        friends == null) {
      return RefreshIndicator(
        onRefresh: _retryLoad,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 120),
            Icon(LucideIcons.triangleAlert, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              l10n.dailySongLoadError,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Center(
              child: FilledButton(
                onPressed: _retryLoad,
                child: Text(l10n.dailySongRetry),
              ),
            ),
          ],
        ),
      );
    }

    final loadedFriends = friends ?? const <AppUser>[];
    final friendsWithSongs = loadedFriends
        .where((friend) => friend.dailySong != null)
        .toList();
    final dailySong = currentUser?.dailySong;
    final hasFriends = (friendIds ?? const <String>[]).isNotEmpty;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleExpiryRefresh(currentUser, loadedFriends);
    });

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ─── Mi canción del día ───
          Text(
            l10n.dailySongYourTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (dailySong != null) ...[
            DailySongCard(
              song: dailySong,
              onTap: () => _openOwnSongMenu(currentUser!),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                DailySongActions(owner: currentUser!),
                TextButton.icon(
                  onPressed: saveState.isSaving ? null : _chooseDailySong,
                  icon: const Icon(LucideIcons.pencil, size: 18),
                  label: Text(l10n.dailySongChoose),
                ),
              ],
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.music,
                      size: 48,
                      color: colorScheme.onSurfaceVariant.withAlpha(128),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.dailySongNone,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.dailySongNoneHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withAlpha(180),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: saveState.isSaving ? null : _chooseDailySong,
                      icon: const Icon(LucideIcons.music),
                      label: Text(l10n.dailySongChoose),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (saveState.hasError) ...[
            const SizedBox(height: 12),
            Card(
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(LucideIcons.triangleAlert, color: colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.dailySongSaveError,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    TextButton(
                      onPressed: _retrySave,
                      child: Text(l10n.dailySongRetry),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (loadError != null) ...[
            const SizedBox(height: 12),
            Card(
              color: colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(LucideIcons.wifiOff, color: colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.dailySongLoadError,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                    TextButton(
                      onPressed: _retryLoad,
                      child: Text(l10n.dailySongRetry),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ─── Canciones de amigos ───
          const SizedBox(height: 24),
          Text(
            l10n.dailySongFriendsTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (hasFriends && friendsWithSongs.isEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l10n.dailySongFriendsNone,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else if (hasFriends)
            ...List.generate(friendsWithSongs.length, (index) {
              final friend = friendsWithSongs[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FriendDailySongCard(
                  friend: friend,
                  onTapSong: () => _openFriendSongMenu(friend),
                  onTapProfile: () => _openProfile(friend),
                ),
              );
            }),
          const InviteFriendsCard(),
        ],
      ),
    );
  }
}
