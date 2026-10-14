import 'package:material_ui/material_ui.dart';
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

  void setThemeMode(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    _persist(mode);
  }

  void _persist(ThemeMode mode) {
    final key = _values.entries.firstWhere((e) => e.value == mode).key;
    ref.read(sharedPreferencesProvider).setString(_kThemeKey, key);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
