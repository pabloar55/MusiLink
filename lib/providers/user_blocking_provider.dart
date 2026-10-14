import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/session_scope_provider.dart';
import 'package:musi_link/providers/user_profile_provider.dart';

/// Punto único para bloquear y desbloquear usuarios. Además de escribir la
/// lista de bloqueados, descarta el estado que deriva de ella: la caché de
/// descubrimiento, los resultados visibles en Discover y la relación con el
/// usuario afectado.
class UserBlockingController {
  UserBlockingController(this._ref);

  final Ref _ref;

  /// Bloquea a [uid]. Si la escritura falla, propaga el error y no toca el
  /// estado derivado.
  Future<void> block(String uid) async {
    final scope = _ref.read(sessionScopeProvider);
    await _ref.read(friendServiceProvider).blockUser(uid);
    // Si la sesión terminó durante la escritura, su estado ya se descartó y lo
    // actual pertenece a otro usuario.
    if (_ref.read(sessionScopeProvider) != scope) return;
    _invalidateDerivedState(uid, (discover) => discover.hideBlockedUser(uid));
  }

  /// Desbloquea a [uid]. Si la escritura falla, propaga el error y no toca el
  /// estado derivado.
  Future<void> unblock(String uid) async {
    final scope = _ref.read(sessionScopeProvider);
    await _ref.read(friendServiceProvider).unblockUser(uid);
    if (_ref.read(sessionScopeProvider) != scope) return;
    _invalidateDerivedState(uid, (discover) => discover.unhideUser(uid));
  }

  void _invalidateDerivedState(
    String uid,
    void Function(DiscoverNotifier discover) updateVisibility,
  ) {
    // La caché recuerda los bloqueados: hay que vaciarla antes de recargar.
    _ref.read(musicProfileServiceProvider).clearCache();
    final discover = _ref.read(discoverProvider.notifier);
    updateVisibility(discover);
    unawaited(discover.refresh());
    _ref.invalidate(relationshipProvider(uid));
  }
}

final userBlockingControllerProvider = Provider<UserBlockingController>(
  UserBlockingController.new,
);
