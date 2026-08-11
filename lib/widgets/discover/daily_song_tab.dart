import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/widgets/discover/daily_song_card.dart';
import 'package:musi_link/widgets/discover/daily_song_search_sheet.dart';
import 'package:musi_link/widgets/discover/friend_daily_song_card.dart';
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
  Track? _dailySong;
  DateTime? _dailySongExpiresAt;
  Timer? _expiryTimer;
  bool _loading = true;
  List<AppUser> _friendsWithSongs = [];
  List<String> _friendIds = [];

  /// UID of the authenticated user from the Riverpod provider.
  /// Returns empty string on session loss — _loadData guards against this.
  String get _currentUid =>
      ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = _currentUid;
    if (uid.isEmpty) {
      // Session lost — GoRouter will redirect; bail out without crashing.
      if (mounted) setState(() => _loading = false);
      return;
    }
    final user = await ref.read(userServiceProvider).getUser(uid);
    if (!mounted) return;

    final friendIds = await ref.read(friendServiceProvider).getFriends();
    List<AppUser> friendsWithSongs = [];

    if (friendIds.isNotEmpty) {
      final friends = await ref
          .read(userServiceProvider)
          .getUsersByIds(friendIds);
      friendsWithSongs = friends.where((f) => f.dailySong != null).toList();
    }

    setState(() {
      _dailySong = user?.dailySong;
      _dailySongExpiresAt = user?.dailySong == null
          ? null
          : user?.dailySongUpdatedAt?.add(AppUser.dailySongLifetime);
      _friendIds = friendIds;
      _friendsWithSongs = friendsWithSongs;
      _loading = false;
    });
    _scheduleExpiryRefresh();
  }

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
    await ref.read(userServiceProvider).setDailySong(uid, track);
    if (!mounted) return;
    setState(() {
      _dailySong = track;
      _dailySongExpiresAt = DateTime.now().add(AppUser.dailySongLifetime);
    });
    _scheduleExpiryRefresh();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final expirations = <DateTime>[
      if (_dailySong != null && _dailySongExpiresAt != null)
        _dailySongExpiresAt!,
      for (final friend in _friendsWithSongs)
        if (friend.dailySong != null && friend.dailySongUpdatedAt != null)
          friend.dailySongUpdatedAt!.add(AppUser.dailySongLifetime),
    ].where((expiry) => expiry.isAfter(now)).toList();
    if (expirations.isEmpty) return;
    expirations.sort();

    _expiryTimer = Timer(expirations.first.difference(now), () {
      if (!mounted) return;
      final expiredAt = DateTime.now();
      setState(() {
        if (_dailySongExpiresAt != null &&
            !_dailySongExpiresAt!.isAfter(expiredAt)) {
          _dailySong = null;
          _dailySongExpiresAt = null;
        }
        _friendsWithSongs = _friendsWithSongs
            .where((friend) => friend.isDailySongActiveAt(expiredAt))
            .toList();
      });
      _scheduleExpiryRefresh();
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _openSpotifyUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return const SkeletonShimmer(child: SkeletonDailySongTab());
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await _loadData();
      },
      child: ListView(
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
          if (_dailySong != null) ...[
            DailySongCard(song: _dailySong!),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _chooseDailySong,
                icon: const Icon(LucideIcons.pencil, size: 18),
                label: Text(l10n.dailySongChoose),
              ),
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
                      onPressed: _chooseDailySong,
                      icon: const Icon(LucideIcons.music),
                      label: Text(l10n.dailySongChoose),
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
          if (_friendIds.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l10n.dailySongNoFriends,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else if (_friendsWithSongs.isEmpty)
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
            )
          else
            ...List.generate(_friendsWithSongs.length, (index) {
              final friend = _friendsWithSongs[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FriendDailySongCard(
                  friend: friend,
                  onTapSong: friend.dailySong!.spotifyUrl.isNotEmpty
                      ? () => _openSpotifyUrl(friend.dailySong!.spotifyUrl)
                      : null,
                  onTapProfile: () => context.push('/profile', extra: friend),
                ),
              );
            }),
        ],
      ),
    );
  }
}
