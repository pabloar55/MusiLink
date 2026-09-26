import 'package:web/web.dart' as web;
import 'package:musi_link/utils/pwa_user_agent.dart';

/// Whether the page is running from an installed PWA window.
///
/// On iPhone and iPad, Web Push is available only in this display mode.
bool get isRunningAsInstalledPwa =>
    web.window.matchMedia('(display-mode: standalone)').matches;

bool get isIosWebPlatform {
  final navigator = web.window.navigator;
  final userAgent = navigator.userAgent;
  return RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent) ||
      (navigator.platform == 'MacIntel' && navigator.maxTouchPoints > 1);
}

bool get usesIos27PwaInstallMenu =>
    isIosWebPlatform &&
    safariMajorVersionFromUserAgent(web.window.navigator.userAgent) >= 27;
