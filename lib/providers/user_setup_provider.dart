import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/user_setup_controller.dart';

/// Estado del alta leído en `main` antes de crear el router.
final userSetupBootstrapStateProvider = Provider<UserSetupBootstrapState?>(
  (ref) => null,
);

final userSetupControllerProvider = Provider<UserSetupController>((ref) {
  // El router conserva esta instancia: solo se observan dependencias estables.
  final repository = ref.read(userSetupRepositoryProvider);
  final controller = UserSetupController(
    auth: ref.watch(firebaseAuthProvider),
    fetchUserState: repository.fetch,
    readCachedUserState: repository.readCached,
    persistUserState: repository.persist,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
