import 'package:material_ui/material_ui.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/track_artwork.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final int? rank;

  const TrackTile({super.key, required this.track, this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS,
      ),
      child: Row(
        children: [
          // Número de ranking
          if (rank != null)
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: tt.labelMedium?.copyWith(
                  fontWeight: rank! <= 3 ? FontWeight.w700 : FontWeight.w400,
                  color: rank! <= 3 ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          if (rank != null) const SizedBox(width: AppTokens.spaceSM),

          // Carátula
          TrackArtwork(
            imageUrl: track.imageUrl,
            width: 52,
            height: 52,
            borderRadius: BorderRadius.circular(AppTokens.radiusSM),
          ),
          const SizedBox(width: AppTokens.spaceMD),

          // Título + artista
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
