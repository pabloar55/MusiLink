import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/artist_tile.dart';
import 'package:musi_link/widgets/genre_tile.dart';

class MusicTasteSection extends StatelessWidget {
  final AppUser user;

  const MusicTasteSection({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        if (user.topArtists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.profileTopArtists,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...user.topArtists.map((artist) => ArtistTile(artist: artist)),
        ],
        if (user.topGenres.isNotEmpty) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.profileTopGenres,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...user.topGenres.asMap().entries.map(
                (entry) => GenreTile(genre: entry.value, rank: entry.key + 1),
              ),
        ],
      ],
    );
  }
}
