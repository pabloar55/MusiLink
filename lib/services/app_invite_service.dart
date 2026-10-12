import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

enum AppInviteResult { shared, copied }

class AppInviteService {
  const AppInviteService();

  /// Enlace para compartir la app: `web/index.html` envía Android a Google
  /// Play y deja que el resto continúe hacia la PWA.
  static const inviteUrl = 'https://musilink.app/invite';

  /// Enlace al perfil de [username]. La app instalada lo abre en la ruta
  /// `/u/:username`; sin ella se comporta como [inviteUrl].
  static String profileUrl(String username) =>
      'https://musilink.app/u/${Uri.encodeComponent(username)}';

  /// Abre el panel de compartir del sistema. Si el navegador no lo ofrece,
  /// copia el mensaje al portapapeles.
  Future<AppInviteResult> share(String message, {Rect? origin}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          sharePositionOrigin: origin,
          mailToFallbackEnabled: false,
        ),
      );
      return AppInviteResult.shared;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: message));
      return AppInviteResult.copied;
    }
  }
}
