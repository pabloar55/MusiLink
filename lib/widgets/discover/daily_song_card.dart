import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/utils/spotify_url.dart';
import 'package:musi_link/widgets/track_artwork.dart';
import 'package:url_launcher/url_launcher.dart';

class DailySongCard extends StatelessWidget {
  final Track song;

  const DailySongCard({super.key, required this.song});

  Future<void> _openSpotify(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spotifyUri = parseSpotifyTrackUri(song.spotifyUrl);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: spotifyUri == null ? null : () => _openSpotify(spotifyUri),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              TrackArtwork(
                imageUrl: song.imageUrl,
                width: 56,
                height: 56,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              Icon(
                LucideIcons.externalLink,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
