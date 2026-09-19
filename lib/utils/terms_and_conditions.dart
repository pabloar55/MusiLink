/// Versión publicada en musilink-site/terms-and-conditions/index.html.
/// Actualizar junto con la callable antes de exigir una versión nueva.
abstract final class TermsAndConditions {
  static const version = '2026-09-18';

  static Uri urlForLocale(String languageCode) {
    final language = switch (languageCode) {
      'es' || 'fr' || 'el' => languageCode,
      _ => 'en',
    };
    return Uri.https(
      'pabloar55.github.io',
      '/musilink-site/terms-and-conditions/',
      {'lang': language},
    );
  }

  static Uri privacyUrlForLocale(String languageCode) {
    final language = switch (languageCode) {
      'es' || 'fr' || 'el' => languageCode,
      _ => 'en',
    };
    return Uri.https('pabloar55.github.io', '/musilink-site/privacy-policy/', {
      'lang': language,
    });
  }
}
