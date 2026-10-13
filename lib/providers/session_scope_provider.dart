import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/firebase_providers.dart';

/// Uid del usuario con sesión, o null si no hay ninguna. Quien lo observa se
/// reconstruye solo cuando cambia el usuario, no en cada evento de sesión.
final sessionUidProvider = Provider<String?>((ref) {
  // Mientras el stream no ha emitido, Firebase ya conoce la sesión restaurada.
  return ref.watch(authStateProvider).asData?.value?.uid ??
      ref.watch(firebaseAuthProvider).currentUser?.uid;
});

/// Generación de la sesión: cambia cada vez que se descarta el estado de un
/// usuario. Un provider con estado propio del usuario la observa con
/// `ref.watch` y así se reconstruye al terminar la sesión. Los que derivan de
/// [sessionUidProvider] ya se reconstruyen con el uid y no la necesitan.
class SessionScopeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Descarta el estado de los providers ligados a la sesión.
  void reset() => state++;
}

final sessionScopeProvider = NotifierProvider<SessionScopeNotifier, int>(
  SessionScopeNotifier.new,
);
