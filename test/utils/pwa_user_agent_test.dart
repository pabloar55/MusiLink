import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/pwa_user_agent.dart';

void main() {
  test('detecta Safari 26 aunque la versión de iOS esté congelada', () {
    const userAgent =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 '
        'Mobile/15E148 Safari/604.1';

    expect(safariMajorVersionFromUserAgent(userAgent), 26);
  });

  test('detecta Safari 27 por Version y no por la versión de iOS', () {
    const userAgent =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 '
        'Mobile/15E148 Safari/604.1';

    expect(safariMajorVersionFromUserAgent(userAgent), 27);
  });

  test('devuelve cero cuando el navegador no expone Version', () {
    const userAgent =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0 '
        'Mobile/15E148 Safari/604.1';

    expect(safariMajorVersionFromUserAgent(userAgent), 0);
  });
}
