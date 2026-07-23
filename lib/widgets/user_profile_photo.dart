import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Displays a user profile photo with a browser-safe fallback.
///
/// Firebase Storage images may not expose the CORS headers required by
/// Flutter's canvas renderer. On web, [WebHtmlElementStrategy.fallback] retries
/// those images as an HTML image element, which can display them without
/// weakening the Storage read rules.
class UserProfilePhoto extends StatelessWidget {
  const UserProfilePhoto({
    super.key,
    required this.photoUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String photoUrl;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl.trim();
    if (url.isEmpty) return fallback;

    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
