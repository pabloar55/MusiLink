import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/trusted_media_url.dart';

class ArtistTile extends StatelessWidget {
  final Artist artist;
  final int? rank;

  const ArtistTile({super.key, required this.artist, this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final imageUrl = trustedSpotifyImageUrl(artist.imageUrl);

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
          ClipOval(
            child: imageUrl.isNotEmpty
                ? _artistImage(cs, imageUrl)
                : _placeholder(cs),
          ),
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

  Widget _artistImage(ColorScheme cs, String imageUrl) {
    if (kIsWeb) {
      return Image.network(
        imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        webHtmlElementStrategy: WebHtmlElementStrategy.never,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(cs),
        errorBuilder: (context, error, stackTrace) => _placeholder(cs),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: 52,
      height: 52,
      fit: BoxFit.cover,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => _placeholder(cs),
      errorWidget: (context, url, error) => _placeholder(cs),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      width: 52,
      height: 52,
      color: cs.surfaceContainerHighest,
      child: Icon(LucideIcons.user, size: 28, color: cs.onSurfaceVariant),
    );
  }
}
