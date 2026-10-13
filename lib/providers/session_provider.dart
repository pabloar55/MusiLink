import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/profile_photo_upload_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/utils/error_reporter.dart';

/// Punto único de cierre de sesión. Vive en un provider para que la limpieza
/// termine aunque la pantalla que la inició se desmonte durante el cierre.
class SessionController {
  SessionController(this._ref);

  final Ref _ref;

  /// Cierra la sesión y descarta el estado del usuario saliente. Si el cierre
  /// falla, propaga el error y conserva el estado de la sesión.
  Future<void> signOut() async {
    await _ref.read(authServiceProvider).signOut();
    _clearState();
  }

  /// Cierra la sesión tras solicitar el borrado de la cuenta. No falla: la
  /// cuenta ya está congelada y la sesión local debe terminar en cualquier
  /// caso. Los tokens se eliminan desde el worker; intentar borrarlos desde el
  /// cliente ya está bloqueado por las reglas tras crear el job.
  Future<void> signOutAfterDeletionRequest() async {
    final authService = _ref.read(authServiceProvider);
    _clearState();
    try {
      await authService.signOut(clearNotificationToken: false);
    } catch (error, stack) {
      reportError(error, stack).ignore();
      try {
        await _ref.read(firebaseAuthProvider).signOut();
      } catch (_) {}
    }
  }

  void _clearState() {
    _ref.read(chatServiceProvider).clearCache();
    _ref.read(musicProfileServiceProvider).clearCache();
    _ref.read(userServiceProvider).clearCache();
    _ref.read(activeChatIdProvider.notifier).setChat(null);
    _ref.read(pendingNotificationProvider.notifier).setValue(null);
    _ref.read(activeReactionPickerProvider.notifier).close();

    _ref.invalidate(authStateProvider);
    _ref.invalidate(profilePhotoUploadProvider);
    _ref.invalidate(currentUserProvider);
    _ref.invalidate(userStreamProvider);
    _ref.invalidate(compatibilityProvider);
    _ref.invalidate(relationshipProvider);
    _ref.invalidate(receivedRequestsProvider);
    _ref.invalidate(sentRequestsProvider);
    _ref.invalidate(friendsStreamProvider);
    _ref.invalidate(chatsProvider);
    _ref.invalidate(unreadChatsCountProvider);
    _ref.invalidate(discoverProvider);
  }
}

final sessionControllerProvider = Provider<SessionController>(
  SessionController.new,
);
