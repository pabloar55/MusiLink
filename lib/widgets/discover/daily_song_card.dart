import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/widgets/track_artwork.dart';

class DailySongCard extends StatelessWidget {
  final Track song;
  final VoidCallback? onTap;

  const DailySongCard({super.key, required this.song, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TrackArtwork(
                imageUrl: song.imageUrl,
                width: 64,
                height: 64,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onTap,
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                color: colorScheme.onSurfaceVariant,
                icon: const Icon(LucideIcons.ellipsis, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
