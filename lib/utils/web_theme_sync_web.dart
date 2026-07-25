import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _darkBackground = '#121212';
const _lightBackground = '#ffffff';

/// Keeps browser and installed-PWA chrome aligned with Flutter's active theme.
void syncWebTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final background = isDark ? _darkBackground : _lightBackground;
  final themeName = isDark ? 'dark' : 'light';

  web.document.documentElement?.setAttribute('data-app-theme', themeName);
  web.document
      .querySelector('meta[name="theme-color"]')
      ?.setAttribute('content', background);
  web.document
      .querySelector('meta[name="color-scheme"]')
      ?.setAttribute('content', themeName);
  web.document
      .querySelector('meta[name="apple-mobile-web-app-status-bar-style"]')
      ?.setAttribute('content', isDark ? 'black-translucent' : 'default');
}
