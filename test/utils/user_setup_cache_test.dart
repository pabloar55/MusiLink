import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/user_setup_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persiste el setup de forma independiente por UID', () async {
    final prefs = await SharedPreferences.getInstance();
    const complete = CachedUserSetupState(
      usernameSet: true,
      artistsSelected: true,
      onboardingDone: true,
      photoSetupDone: true,
    );

    await UserSetupCache.write(prefs, 'user-a', complete);

    final restored = UserSetupCache.read(prefs, 'user-a');
    expect(restored, isNotNull);
    expect(restored!.usernameSet, isTrue);
    expect(restored.artistsSelected, isTrue);
    expect(UserSetupCache.read(prefs, 'user-b'), isNull);
  });

  test('ignora snapshots corruptos', () async {
    SharedPreferences.setMockInitialValues({
      'user_setup_state_v1_user-a': '{invalid-json',
    });
    final prefs = await SharedPreferences.getInstance();

    expect(UserSetupCache.read(prefs, 'user-a'), isNull);
  });
}
