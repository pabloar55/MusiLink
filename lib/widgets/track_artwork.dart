import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/utils/trusted_media_url.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.iconSize,
  });

  final String imageUrl;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final trustedUrl = trustedSpotifyImageUrl(imageUrl);
    final content = trustedUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: trustedUrl,
            width: width,
            height: height,
            fit: fit,
            useOldImageOnUrlChange: true,
            placeholder: (context, url) => _placeholder(colorScheme),
            errorWidget: (context, url, error) => _placeholder(colorScheme),
            errorListener: (_) {},
          )
        : _placeholder(colorScheme);

    if (borderRadius == null) return content;

    return ClipRRect(borderRadius: borderRadius!, child: content);
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        LucideIcons.music,
        size: iconSize ?? _defaultIconSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  double get _defaultIconSize {
    if (height.isFinite) return height * 0.48;
    return 28;
  }
}
