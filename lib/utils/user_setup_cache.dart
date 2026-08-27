import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedUserSetupState {
  const CachedUserSetupState({
    required this.usernameSet,
    required this.artistsSelected,
    required this.onboardingDone,
    required this.photoSetupDone,
  });

  final bool usernameSet;
  final bool artistsSelected;
  final bool onboardingDone;
  final bool photoSetupDone;

  Map<String, bool> toJson() => {
    'usernameSet': usernameSet,
    'artistsSelected': artistsSelected,
    'onboardingDone': onboardingDone,
    'photoSetupDone': photoSetupDone,
  };

  static CachedUserSetupState? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final usernameSet = value['usernameSet'];
    final artistsSelected = value['artistsSelected'];
    final onboardingDone = value['onboardingDone'];
    final photoSetupDone = value['photoSetupDone'];
    if (usernameSet is! bool ||
        artistsSelected is! bool ||
        onboardingDone is! bool ||
        photoSetupDone is! bool) {
      return null;
    }
    return CachedUserSetupState(
      usernameSet: usernameSet,
      artistsSelected: artistsSelected,
      onboardingDone: onboardingDone,
      photoSetupDone: photoSetupDone,
    );
  }
}

class UserSetupCache {
  const UserSetupCache._();

  static const _keyPrefix = 'user_setup_state_v1_';

  static CachedUserSetupState? read(SharedPreferences prefs, String uid) {
    final raw = prefs.getString('$_keyPrefix$uid');
    if (raw == null) return null;
    try {
      return CachedUserSetupState.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    SharedPreferences prefs,
    String uid,
    CachedUserSetupState state,
  ) {
    return prefs.setString('$_keyPrefix$uid', jsonEncode(state.toJson()));
  }
}
