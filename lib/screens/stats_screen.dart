import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/music_profile_sync_provider.dart';
import 'package:musi_link/widgets/artist_tile.dart';
import 'package:musi_link/widgets/genre_tile.dart';
import 'package:musi_link/widgets/filter_button.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

enum _Tab { artists, genres }

class _StatsScreenState extends ConsumerState<StatsScreen>
    with AutomaticKeepAliveClientMixin<StatsScreen> {
  _Tab _tab = _Tab.artists;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final userAsync = ref.watch(effectiveCurrentUserProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              FilterButton(
                label: l10n.statsArtists,
                isSelected: _tab == _Tab.artists,
                onPressed: () => setState(() => _tab = _Tab.artists),
              ),
              const SizedBox(width: 8),
              FilterButton(
                label: l10n.statsGenres,
                isSelected: _tab == _Tab.genres,
                onPressed: () => setState(() => _tab = _Tab.genres),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: Text(l10n.statsEditArtists),
                onPressed: () => context.push('/artist-edit'),
              ),
            ],
          ),
        ),
        Expanded(
          child: userAsync.when(
            loading: () => SkeletonShimmer(
              child: ListView.builder(
                itemCount: 8,
                itemBuilder: (_, _) => const SkeletonStatsTile(),
              ),
            ),
            error: (err, st) => Center(child: Text(l10n.statsNoData)),
            data: (user) {
              if (user == null) {
                return Center(child: Text(l10n.statsNoData));
              }
              if (_tab == _Tab.artists) {
                if (user.topArtists.isEmpty) {
                  return Center(child: Text(l10n.statsNoData));
                }
                return ListView.builder(
                  itemCount: user.topArtists.length,
                  itemBuilder: (_, i) =>
                      ArtistTile(artist: user.topArtists[i], rank: i + 1),
                );
              } else {
                if (user.topGenres.isEmpty) {
                  return Center(child: Text(l10n.statsNoData));
                }
                return ListView.builder(
                  itemCount: user.topGenres.length,
                  itemBuilder: (_, i) =>
                      GenreTile(genre: user.topGenres[i], rank: i + 1),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
