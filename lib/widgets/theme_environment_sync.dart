import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musi_link/utils/web_theme_sync.dart';

/// Mirrors Flutter's resolved theme into the surrounding platform chrome.
class ThemeEnvironmentSync extends StatefulWidget {
  const ThemeEnvironmentSync({required this.child, super.key});

  final Widget child;

  @override
  State<ThemeEnvironmentSync> createState() => _ThemeEnvironmentSyncState();
}

class _ThemeEnvironmentSyncState extends State<ThemeEnvironmentSync> {
  Brightness? _lastBrightness;
  Color? _lastNavigationBarColor;
  SystemUiOverlayStyle? _androidOverlayStyle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final navigationBarColor =
        theme.navigationBarTheme.backgroundColor ?? theme.colorScheme.surface;
    if (_lastBrightness == brightness &&
        _lastNavigationBarColor == navigationBarColor) {
      return;
    }

    _lastBrightness = brightness;
    _lastNavigationBarColor = navigationBarColor;
    syncWebTheme(brightness);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _androidOverlayStyle = SystemUiOverlayStyle(
        systemNavigationBarColor: navigationBarColor,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        // Android adds a dark contrast scrim in three-button navigation by
        // default. The app bar already provides an accessible solid color.
        systemNavigationBarContrastEnforced: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayStyle = _androidOverlayStyle;
    if (overlayStyle == null) return widget.child;

    // Keeping this style in the layer tree lets Flutter combine it with an
    // AppBar's status-bar style and reapply the lower bar after theme changes.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: widget.child,
    );
  }
}
