import 'package:material_ui/material_ui.dart';
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTapSong,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapProfile,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserCircleAvatar(
                        photoUrl: friend.photoUrl,
                        name: friend.displayName,
                        radius: 14,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          friend.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
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
                    onPressed: onTapSong,
                    tooltip: MaterialLocalizations.of(context)
                        .moreButtonTooltip,
                    color: colorScheme.onSurfaceVariant,
                    icon: const Icon(LucideIcons.ellipsis, size: 22),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DailySongActions(owner: friend),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
