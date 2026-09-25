import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/discover/daily_song_actions.dart';
import 'package:musi_link/widgets/track_artwork.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

class FriendDailySongCard extends StatelessWidget {
  final AppUser friend;
  final VoidCallback? onTapSong;
  final VoidCallback? onTapProfile;

  const FriendDailySongCard({
    super.key,
    required this.friend,
    this.onTapSong,
    this.onTapProfile,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final song = friend.dailySong!;

    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTapSong,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onTapProfile,
                    child: UserCircleAvatar(
                      photoUrl: friend.photoUrl,
                      name: friend.displayName,
                      radius: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TrackArtwork(
                    imageUrl: song.imageUrl,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.artist,
                          style: TextStyle(
                            fontSize: 12,
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
          DailySongActions(owner: friend),
        ],
      ),
    );
  }
}
