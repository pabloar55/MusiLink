import 'package:flutter/material.dart';
import 'package:musi_link/utils/web_theme_sync.dart';

/// Mirrors Flutter's resolved theme into the surrounding web/PWA chrome.
class ThemeEnvironmentSync extends StatefulWidget {
  const ThemeEnvironmentSync({required this.child, super.key});

  final Widget child;

  @override
  State<ThemeEnvironmentSync> createState() => _ThemeEnvironmentSyncState();
}

class _ThemeEnvironmentSyncState extends State<ThemeEnvironmentSync> {
  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness == brightness) return;

    _lastBrightness = brightness;
    syncWebTheme(brightness);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
