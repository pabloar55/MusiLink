import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:musi_link/utils/trusted_media_url.dart';

/// Displays a user profile photo with a browser-safe fallback.
///
/// On web, profile photos stay in Flutter's canvas so they participate in
/// clipping and scroll stretch effects. The Firebase Storage bucket must apply
/// the CORS policy in `cors.json` for cross-origin image requests to work.
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
    final url = trustedProfilePhotoUrl(photoUrl);
    if (url.isEmpty) return fallback;

    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        webHtmlElementStrategy: WebHtmlElementStrategy.never,
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
