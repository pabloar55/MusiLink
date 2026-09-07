import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/utils/trusted_media_url.dart';

/// Circular artist artwork with a consistent loading and error fallback.
///
/// On web, using an [Image] widget avoids the unreliable lifecycle of a
/// cached image provider used as a [CircleAvatar] background image.
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.imageUrl,
    this.size = 52,
    this.iconSize,
  });

  final String imageUrl;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trustedUrl = trustedSpotifyImageUrl(imageUrl);

    return ClipOval(
      child: trustedUrl.isEmpty
          ? _placeholder(colorScheme)
          : _artistImage(colorScheme, trustedUrl),
    );
  }

  Widget _artistImage(ColorScheme colorScheme, String trustedUrl) {
    if (kIsWeb) {
      return Image.network(
        trustedUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        webHtmlElementStrategy: WebHtmlElementStrategy.never,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(colorScheme),
        errorBuilder: (context, error, stackTrace) => _placeholder(colorScheme),
      );
    }

    return CachedNetworkImage(
      imageUrl: trustedUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => _placeholder(colorScheme),
      errorWidget: (context, url, error) => _placeholder(colorScheme),
      errorListener: (_) {},
    );
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        LucideIcons.user,
        size: iconSize ?? size * 0.54,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
