import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/utils/retry_backoff.dart';

/// Pasos del alta completados por la cuenta de la sesión actual.
///
/// Parte del snapshot de arranque o de la caché del UID, lo refresca desde el
/// servidor con reintentos y conserva los pasos que las pantallas del alta
/// completan mientras tanto.
class UserSetupController extends ChangeNotifier {
  UserSetupController({
    required this._auth,
    this._fetchUserState,
    this._readCachedUserState,
    this._persistUserState,
  });

  final FirebaseAuth _auth;
  final FetchUserSetupState? _fetchUserState;
  final ReadCachedUserSetupState? _readCachedUserState;
  final PersistUserSetupState? _persistUserState;

  final _retryBackoff = RetryBackoff();
  Timer? _retryTimer;
  int _authGeneration = 0;
  int _revision = 0;
  String? _stateUid;
  bool _usernameSet = false;
  bool _artistsSelected = false;
  bool _onboardingDone = false;
  bool _photoSetupDone = false;
  bool _deletionPending = false;
  bool _setupStateKnown = false;

  bool get usernameSet => _usernameSet;
  bool get artistsSelected => _artistsSelected;
  bool get onboardingDone => _onboardingDone;
  bool get photoSetupDone => _photoSetupDone;
  bool get deletionPending => _deletionPending;
  bool get setupStateKnown => _setupStateKnown;

  /// Aplica el snapshot leído durante el arranque.
  void restore(UserSetupBootstrapState state) {
    _usernameSet = state.usernameSet;
    _artistsSelected = state.artistsSelected;
    _onboardingDone = state.onboardingDone;
    _photoSetupDone = state.photoSetupDone;
    _deletionPending = state.deletionPending;
    _setupStateKnown = state.setupStateKnown;
    _stateUid = state.userUid;
  }

  /// Aplica un cambio de sesión sin avisar a los listeners: quien coordina la
  /// sesión avisa una sola vez tras actualizar también los términos.
  void handleAuthChange(User? user) {
    final generation = ++_authGeneration;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryBackoff.reset();
    if (user == null) {
      _resetSteps();
      _setupStateKnown = true;
      _stateUid = null;
      return;
    }
    if (_fetchUserState == null) return;
    // El estado anterior puede pertenecer a la pantalla sin sesión o a
    // otra cuenta. Solo es seguro reutilizar un snapshot del mismo UID.
    final cachedState = _readCachedState(user.uid);
    if (cachedState != null) {
      _deletionPending = false;
      _applyState(cachedState);
      _setupStateKnown = true;
      _stateUid = user.uid;
    } else if (!_setupStateKnown || _stateUid != user.uid) {
      _resetSteps();
      _setupStateKnown = false;
      _stateUid = user.uid;
    }
    unawaited(_refresh(user, generation));
  }

  /// Llamar desde UsernameSetupScreen tras guardar el username.
  void setUsernameSet() => _completeStep(() => _usernameSet = true);

  /// Llamar después de seleccionar artistas para que el router re-evalúe
  /// y navegue automáticamente al siguiente paso.
  void setArtistsSelected() => _completeStep(() => _artistsSelected = true);

  /// Llamar al completar el onboarding para que el router re-evalúe
  /// y navegue automáticamente a la pantalla de foto de perfil.
  void setOnboardingDone() => _completeStep(() => _onboardingDone = true);

  /// Llamar al completar (o saltar) la configuración de foto de perfil.
  void setPhotoSetupDone() => _completeStep(() => _photoSetupDone = true);

  void _completeStep(void Function() markDone) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _revision++;
    markDone();
    _setupStateKnown = true;
    _stateUid = uid;
    _persistState(uid);
    notifyListeners();
  }

  void _resetSteps() {
    _usernameSet = false;
    _artistsSelected = false;
    _onboardingDone = false;
    _photoSetupDone = false;
    _deletionPending = false;
  }

  UserSetupState? _readCachedState(String uid) {
    try {
      return _readCachedUserState?.call(uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh(User user, int generation) async {
    final revision = _revision;
    try {
      final state = await _fetchUserState!(user.uid);
      if (!_isCurrentAuthUser(user, generation)) return;
      // Un refresco iniciado antes de completar un paso no debe deshacerlo.
      if (_stateUid == user.uid && revision != _revision) {
        _applyState((
          usernameSet: state.usernameSet || _usernameSet,
          artistsSelected: state.artistsSelected || _artistsSelected,
          onboardingDone: state.onboardingDone || _onboardingDone,
          photoSetupDone: state.photoSetupDone || _photoSetupDone,
          deletionPending: state.deletionPending,
        ));
      } else {
        _applyState(state);
      }
      _setupStateKnown = true;
      _stateUid = user.uid;
      _retryBackoff.reset();
      _persistState(user.uid);
      notifyListeners();
    } catch (_) {
      if (!_isCurrentAuthUser(user, generation)) return;
      // Si no había snapshot para este UID, el perfil sigue siendo
      // desconocido. Un fallo de red nunca equivale a un usuario nuevo.
      _scheduleRetry(user, generation);
    }
  }

  bool _isCurrentAuthUser(User user, int generation) =>
      generation == _authGeneration && _auth.currentUser?.uid == user.uid;

  void _applyState(UserSetupState state) {
    _usernameSet = state.usernameSet;
    _artistsSelected = state.artistsSelected;
    _onboardingDone = state.onboardingDone;
    _photoSetupDone = state.photoSetupDone;
    final deletionPending = state.deletionPending;
    if (deletionPending != null) {
      _deletionPending = deletionPending;
    }
  }

  void _scheduleRetry(User user, int generation) {
    if (_retryTimer != null) return;
    _retryTimer = Timer(_retryBackoff.next(), () {
      _retryTimer = null;
      if (_isCurrentAuthUser(user, generation)) {
        unawaited(_refresh(user, generation));
      }
    });
  }

  UserSetupState get _currentState => (
    usernameSet: _usernameSet,
    artistsSelected: _artistsSelected,
    onboardingDone: _onboardingDone,
    photoSetupDone: _photoSetupDone,
    deletionPending: _deletionPending,
  );

  void _persistState(String uid) {
    final persist = _persistUserState;
    if (persist != null) {
      unawaited(_persistIgnoringErrors(persist, uid, _currentState));
    }
  }

  Future<void> _persistIgnoringErrors(
    PersistUserSetupState persist,
    String uid,
    UserSetupState state,
  ) async {
    try {
      await persist(uid, state);
    } catch (_) {
      // La persistencia local mejora el arranque, pero no debe bloquearlo.
    }
  }

  @override
  void dispose() {
    _authGeneration++;
    _retryTimer?.cancel();
    super.dispose();
  }
}
