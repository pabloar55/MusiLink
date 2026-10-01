import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

enum AppInviteResult { shared, copied }

class AppInviteService {
  const AppInviteService();

  /// Enlace único para todas las plataformas: `web/index.html` envía Android a
  /// Google Play y deja que el resto continúe hacia la PWA.
  static const inviteUrl = 'https://musilink.app/invite';

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
