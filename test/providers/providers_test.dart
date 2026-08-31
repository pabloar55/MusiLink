// ignore_for_file: subtype_of_sealed_class
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/theme_provider.dart';
import 'package:musi_link/services/auth_service.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/mocks.dart';

class MockChatService extends Mock implements ChatService {}

class MockFriendService extends Mock implements FriendService {}

class MockAuthService extends Mock implements AuthService {}
class MockSharedPreferences extends Mock implements SharedPreferences {}

ProviderContainer _themeContainer({String? savedMode}) {
  final mockPrefs = MockSharedPreferences();
  when(() => mockPrefs.getString('theme_mode')).thenReturn(savedMode);
  when(() => mockPrefs.setString(any(), any())).thenAnswer((_) async => true);
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Service Providers con overrides', () {
    test('authServiceProvider puede ser sustituido con mock', () {
      final mockAuth = MockAuthService();
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(mockAuth),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authServiceProvider), same(mockAuth));
    });

    test('providers devuelven mocks cuando se hace override', () {
      final mockUserService = MockUserService();
      final mockChatService = MockChatService();
      final mockFriendService = MockFriendService();

      final container = ProviderContainer(
        overrides: [
          userServiceProvider.overrideWithValue(mockUserService),
          chatServiceProvider.overrideWithValue(mockChatService),
          friendServiceProvider.overrideWithValue(mockFriendService),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(userServiceProvider), same(mockUserService));
      expect(container.read(chatServiceProvider), same(mockChatService));
      expect(container.read(friendServiceProvider), same(mockFriendService));
    });
  });

  group('ThemeModeNotifier', () {
    test('estado inicial es ThemeMode.dark', () {
      final container = _themeContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('toggleDarkLight alterna entre dark y light', () {
      final container = _themeContainer(savedMode: 'light');
      addTearDown(container.dispose);

      final notifier = container.read(themeModeProvider.notifier);

      // light -> dark
      notifier.toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      // dark -> light
      notifier.toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.light);

      // light -> dark
      notifier.toggleDarkLight();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('setThemeMode permite seleccionar system, light y dark', () {
      final container = _themeContainer(savedMode: 'dark');
      addTearDown(container.dispose);

      final notifier = container.read(themeModeProvider.notifier);

      notifier.setThemeMode(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);

      notifier.setThemeMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);

      notifier.setThemeMode(ThemeMode.dark);
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('isDarkProvider', () {
    test('devuelve false en modo system con platform brightness light', () {
      final container = _themeContainer(savedMode: 'system');
      addTearDown(container.dispose);

      expect(container.read(isDarkProvider), false);
    });

    test('devuelve true cuando el tema es dark', () {
      final container = _themeContainer(savedMode: 'dark');
      addTearDown(container.dispose);

      expect(container.read(isDarkProvider), true);
    });

    test('devuelve false cuando el tema es light', () {
      final container = _themeContainer(savedMode: 'light');
      addTearDown(container.dispose);

      expect(container.read(isDarkProvider), false);
    });
  });
}
