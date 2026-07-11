import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';

const _kThemeKey = 'theme_mode';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _values = {
    'dark': ThemeMode.dark,
    'light': ThemeMode.light,
    'system': ThemeMode.system,
  };

  @override
  ThemeMode build() {
    // Carga sincrónica desde el SharedPreferences ya inicializado en main.
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getString(_kThemeKey);
    return _values[saved] ?? (kIsWeb ? ThemeMode.system : ThemeMode.dark);
  }

  bool get isDark {
    if (state == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return state == ThemeMode.dark;
  }

  void toggleDarkLight() {
    state = isDark ? ThemeMode.light : ThemeMode.dark;
    _persist(state);
  }

  void _persist(ThemeMode mode) {
    final key = _values.entries.firstWhere((e) => e.value == mode).key;
    ref.read(sharedPreferencesProvider).setString(_kThemeKey, key);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Provider derivado que indica si el tema actual es oscuro.
final isDarkProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.system) {
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }
  return mode == ThemeMode.dark;
});
