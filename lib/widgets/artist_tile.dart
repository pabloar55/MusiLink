import 'package:flutter/material.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/artist_avatar.dart';

class ArtistTile extends StatelessWidget {
  final Artist artist;
  final int? rank;

  const ArtistTile({super.key, required this.artist, this.rank});

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

          // Foto circular del artista
          ArtistAvatar(imageUrl: artist.imageUrl),
          const SizedBox(width: AppTokens.spaceMD),

          // Nombre
          Expanded(
            child: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
