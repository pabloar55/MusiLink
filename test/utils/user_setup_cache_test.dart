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
      'user_setup_state_v2_user-a': '{invalid-json',
    });
    final prefs = await SharedPreferences.getInstance();

    expect(UserSetupCache.read(prefs, 'user-a'), isNull);
  });
  test('ignora flags globales y snapshots v1 contaminados', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'photo_setup_done': true,
      'user_setup_state_v1_user-b': '{"usernameSet":true,"artistsSelected":false,"onboardingDone":true,"photoSetupDone":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    final state = UserSetupCache.resolve(
      prefs,
      'user-b',
      usernameSet: true,
      artistsSelected: false,
    );
    expect(state.onboardingDone, isFalse);
    expect(state.photoSetupDone, isFalse);
  });

  test('terminar onboarding no completa la foto al reiniciar', () async {
    final prefs = await SharedPreferences.getInstance();
    await UserSetupCache.write(
      prefs,
      'user-a',
      const CachedUserSetupState(
        usernameSet: true,
        artistsSelected: false,
        onboardingDone: true,
        photoSetupDone: false,
      ),
    );
    final state = UserSetupCache.resolve(
      prefs,
      'user-a',
      usernameSet: true,
      artistsSelected: false,
    );
    expect(state.onboardingDone, isTrue);
    expect(state.photoSetupDone, isFalse);
    final other = UserSetupCache.resolve(
      prefs,
      'user-b',
      usernameSet: false,
      artistsSelected: false,
    );
    expect(other.onboardingDone, isFalse);
    expect(other.photoSetupDone, isFalse);
  });

  test(
    'recupera cuentas antiguas completas desde su propio perfil musical',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final state = UserSetupCache.resolve(
        prefs,
        'user-a',
        usernameSet: true,
        artistsSelected: true,
      );
      expect(state.onboardingDone, isTrue);
      expect(state.photoSetupDone, isTrue);
    },
  );
}
