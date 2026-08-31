import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

typedef UserSetupState = ({
  bool usernameSet,
  bool artistsSelected,
  bool onboardingDone,
  bool photoSetupDone,
  bool? deletionPending,
});

typedef FetchUserSetupState = Future<UserSetupState> Function(String uid);
typedef ReadCachedUserSetupState = UserSetupState? Function(String uid);
typedef PersistUserSetupState = Future<void> Function(
  String uid,
  UserSetupState state,
);

class AppRouterBootstrapState {
  const AppRouterBootstrapState({
    required this.usernameSet,
    required this.artistsSelected,
    required this.onboardingDone,
    required this.photoSetupDone,
    required this.deletionPending,
    required this.setupStateKnown,
    this.userUid,
  });

  final bool usernameSet;
  final bool artistsSelected;
  final bool onboardingDone;
  final bool photoSetupDone;
  final bool deletionPending;
  final bool setupStateKnown;
  final String? userUid;
}

/// Notifier que dispara los redirects de GoRouter cuando cambia
/// el estado de autenticación o cuando la app termina la inicialización.
class AppRouterNotifier extends ChangeNotifier {
  final FirebaseAuth _auth;

  AppRouterNotifier({
    required this._auth,
    AppRouterBootstrapState? initialState,
    FetchUserSetupState? fetchUserState,
    ReadCachedUserSetupState? readCachedUserState,
    PersistUserSetupState? persistUserState,
  }) {
    if (initialState != null) {
      setInitialized(
        usernameSet: initialState.usernameSet,
        artistsSelected: initialState.artistsSelected,
        onboardingDone: initialState.onboardingDone,
        photoSetupDone: initialState.photoSetupDone,
        deletionPending: initialState.deletionPending,
        setupStateKnown: initialState.setupStateKnown,
        setupStateUid: initialState.userUid,
        fetchUserState: fetchUserState,
        readCachedUserState: readCachedUserState,
        persistUserState: persistUserState,
      );
    }
  }

  StreamSubscription<User?>? _sub;
  Timer? _retryTimer;
  int _authGeneration = 0;
  int _retryAttempt = 0;
  String? _setupStateUid;
  bool _initialized = false;
  bool _usernameSet = false;
  bool _artistsSelected = false;
  bool _onboardingDone = false;
  bool _photoSetupDone = false;
  bool _deletionPending = false;
  bool _setupStateKnown = false;

  bool get isInitialized => _initialized;
  bool get isLoggedIn => _auth.currentUser != null;
  bool get usernameSet => _usernameSet;
  bool get artistsSelected => _artistsSelected;
  bool get onboardingDone => _onboardingDone;
  bool get photoSetupDone => _photoSetupDone;
  bool get deletionPending => _deletionPending;
  bool get setupStateKnown => _setupStateKnown;

  FetchUserSetupState? _fetchUserState;
  ReadCachedUserSetupState? _readCachedUserState;
  PersistUserSetupState? _persistUserState;

  /// Marca el router como inicializado, inicia la escucha de authStateChanges
  /// y dispara el primer redirect.
  void setInitialized({
    required bool usernameSet,
    required bool artistsSelected,
    required bool onboardingDone,
    required bool photoSetupDone,
    bool deletionPending = false,
    bool setupStateKnown = true,
    String? setupStateUid,
    FetchUserSetupState? fetchUserState,
    ReadCachedUserSetupState? readCachedUserState,
    PersistUserSetupState? persistUserState,
  }) {
    _initialized = true;
    _usernameSet = usernameSet;
    _artistsSelected = artistsSelected;
    _onboardingDone = onboardingDone;
    _photoSetupDone = photoSetupDone;
    _deletionPending = deletionPending;
    _setupStateKnown = setupStateKnown;
    _setupStateUid = setupStateUid;
    _fetchUserState = fetchUserState;
    _readCachedUserState = readCachedUserState;
    _persistUserState = persistUserState;
    _sub?.cancel();
    _sub = _auth.authStateChanges().listen((user) {
      final generation = ++_authGeneration;
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempt = 0;
      if (user == null) {
        _usernameSet = false;
        _artistsSelected = false;
        _onboardingDone = false;
        _photoSetupDone = false;
        _deletionPending = false;
        _setupStateKnown = true;
        _setupStateUid = null;
        notifyListeners();
      } else if (_fetchUserState != null) {
        // El estado anterior puede pertenecer a la pantalla sin sesión o a
        // otra cuenta. Solo es seguro reutilizar un snapshot del mismo UID.
        final cachedState = _readCachedState(user.uid);
        if (cachedState != null) {
          _deletionPending = false;
          _applySetupState(cachedState);
          _setupStateKnown = true;
          _setupStateUid = user.uid;
        } else if (!_setupStateKnown || _setupStateUid != user.uid) {
          _usernameSet = false;
          _artistsSelected = false;
          _onboardingDone = false;
          _photoSetupDone = false;
          _deletionPending = false;
          _setupStateKnown = false;
          _setupStateUid = user.uid;
        }
        notifyListeners();
        unawaited(_refreshUserState(user, generation));
      } else {
        notifyListeners();
      }
    });
  }

  UserSetupState? _readCachedState(String uid) {
    try {
      return _readCachedUserState?.call(uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshUserState(User user, int generation) async {
    try {
      final state = await _fetchUserState!(user.uid);
      if (!_isCurrentAuthUser(user, generation)) return;
      _applySetupState(state);
      _setupStateKnown = true;
      _setupStateUid = user.uid;
      _retryAttempt = 0;
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

  void _applySetupState(UserSetupState state) {
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
    const delays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 30),
    ];
    final delay = delays[_retryAttempt.clamp(0, delays.length - 1)];
    if (_retryAttempt < delays.length - 1) _retryAttempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_isCurrentAuthUser(user, generation)) {
        unawaited(_refreshUserState(user, generation));
      }
    });
  }

  /// Llamar desde UsernameSetupScreen tras guardar el username.
  void setUsernameSet() {
    _usernameSet = true;
    _setupStateKnown = true;
    _setupStateUid = _auth.currentUser?.uid;
    _persistCurrentState();
    notifyListeners();
  }

  /// Llamar después de seleccionar artistas para que el router re-evalúe
  /// y navegue automáticamente al siguiente paso.
  void setArtistsSelected() {
    _artistsSelected = true;
    _setupStateKnown = true;
    _setupStateUid = _auth.currentUser?.uid;
    _persistCurrentState();
    notifyListeners();
  }

  /// Llamar al completar el onboarding para que el router re-evalúe
  /// y navegue automáticamente a la pantalla de foto de perfil.
  void setOnboardingDone() {
    _onboardingDone = true;
    _setupStateKnown = true;
    _setupStateUid = _auth.currentUser?.uid;
    _persistCurrentState();
    notifyListeners();
  }

  /// Llamar al completar (o saltar) la configuración de foto de perfil.
  void setPhotoSetupDone() {
    _photoSetupDone = true;
    _setupStateKnown = true;
    _setupStateUid = _auth.currentUser?.uid;
    _persistCurrentState();
    notifyListeners();
  }

  UserSetupState get _currentSetupState => (
    usernameSet: _usernameSet,
    artistsSelected: _artistsSelected,
    onboardingDone: _onboardingDone,
    photoSetupDone: _photoSetupDone,
    deletionPending: _deletionPending,
  );

  void _persistCurrentState() {
    if (_persistUserState == null) return;
    final uid = _auth.currentUser?.uid;
    if (uid != null) _persistState(uid);
  }

  void _persistState(String uid) {
    final persist = _persistUserState;
    if (persist != null) {
      unawaited(_persistIgnoringErrors(persist, uid, _currentSetupState));
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
    _sub?.cancel();
    super.dispose();
  }
}

/// Lógica de redirect centralizada y testeable de forma independiente.
/// Devuelve la ruta destino o null si no hay que redirigir.
String? appRedirect(AppRouterNotifier notifier, String location) {
  if (!notifier.isInitialized) {
    if (!notifier.isLoggedIn) return location == '/auth' ? null : '/auth';
    return null;
  }
  if (!notifier.isLoggedIn) {
    return location == '/auth' ? null : '/auth';
  }
  if (notifier.deletionPending) {
    return location == '/deleting-account' ? null : '/deleting-account';
  }
  if (!notifier.setupStateKnown) {
    if (location == '/auth' ||
        location == '/onboarding' ||
        location == '/username-setup' ||
        location == '/photo-setup' ||
        location == '/artist-select') {
      return '/';
    }
    return null;
  }
  if (!notifier.onboardingDone) {
    return location == '/onboarding' ? null : '/onboarding';
  }
  if (!notifier.usernameSet) {
    return location == '/username-setup' ? null : '/username-setup';
  }
  if (!notifier.photoSetupDone) {
    return location == '/photo-setup' ? null : '/photo-setup';
  }
  if (!notifier.artistsSelected) {
    return location == '/artist-select' ? null : '/artist-select';
  }
  // Usuario listo: evitar que se quede en pantallas de setup
  if (location == '/auth' ||
      location == '/onboarding' ||
      location == '/username-setup' ||
      location == '/photo-setup' ||
      location == '/artist-select') {
    return '/';
  }
  return null;
}
