import 'package:web/web.dart' as web;

const _dismissedKey = 'pwa_install_dismissed';

bool get hasDismissedPwaInstallForSession {
  try {
    return web.window.sessionStorage.getItem(_dismissedKey) == 'true';
  } catch (_) {
    return false;
  }
}

void dismissPwaInstallForSession() {
  try {
    web.window.sessionStorage.setItem(_dismissedKey, 'true');
  } catch (_) {
    // Continuing in the browser must still work when storage is unavailable.
  }
}
