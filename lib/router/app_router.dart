import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/services/terms_acceptance_controller.dart';
import 'package:musi_link/services/user_setup_controller.dart';

/// Notifier que dispara los redirects de GoRouter cuando cambia la sesión, el
/// estado del alta o la aceptación de términos, o cuando la app termina la
/// inicialización.
class AppRouterNotifier extends ChangeNotifier {
  AppRouterNotifier({
    required this._auth,
    required this.setup,
    required this.terms,
    UserSetupBootstrapState? initialState,
  }) {
    setup.addListener(notifyListeners);
    terms.addListener(notifyListeners);
    if (initialState != null) setInitialized(initialState);
  }

  final FirebaseAuth _auth;
  final UserSetupController setup;
  final TermsAcceptanceController terms;
  StreamSubscription<User?>? _sub;
  bool _initialized = false;
  String? _pendingProfileLink;

  /// Enlace de perfil (`/u/:username`) abierto antes de terminar el login o
  /// el alta. Se retoma en cuanto el usuario puede entrar en la app.
  String? get pendingProfileLink => _pendingProfileLink;

  bool get isInitialized => _initialized;
  bool get isLoggedIn => _auth.currentUser != null;

  /// Aplica el estado de arranque, marca el router como inicializado e inicia
  /// la escucha de authStateChanges, que dispara el primer redirect.
  void setInitialized(UserSetupBootstrapState state) {
    _initialized = true;
    setup.restore(state);
    _sub?.cancel();
    _sub = _auth.authStateChanges().listen(_handleAuthChange);
  }

  void _handleAuthChange(User? user) {
    // Ambos estados cambian antes de avisar para que GoRouter nunca evalúe un
    // redirect con los términos de una sesión y el alta de otra.
    terms.handleAuthChange(user);
    setup.handleAuthChange(user);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    setup.removeListener(notifyListeners);
    terms.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Lógica de redirect centralizada y testeable de forma independiente.
/// Devuelve la ruta destino o null si no hay que redirigir.
String? appRedirect(AppRouterNotifier notifier, String location) {
  final target = _redirectFor(notifier, location);
  // Un enlace de perfil que todavía no puede abrirse se conserva para
  // retomarlo cuando terminen el login y el alta.
  if (target != null && isUserProfileLinkLocation(location)) {
    notifier._pendingProfileLink = location;
  }
  return target;
}

String? _redirectFor(AppRouterNotifier notifier, String location) {
  // Destino al salir de las pantallas de acceso y alta.
  final home = notifier._pendingProfileLink ?? '/';
  if (!notifier.isInitialized) {
    if (!notifier.isLoggedIn) return location == '/auth' ? null : '/auth';
    if (notifier.terms.mustAcceptTerms) {
      return location == '/terms' ? null : '/terms';
    }
    return location == '/terms' ? home : null;
  }
  if (!notifier.isLoggedIn) {
    return location == '/auth' ? null : '/auth';
  }
  final setup = notifier.setup;
  if (setup.deletionPending) {
    return location == '/deleting-account' ? null : '/deleting-account';
  }
  if (notifier.terms.mustAcceptTerms) {
    return location == '/terms' || location == '/privacy-policy'
        ? null
        : '/terms';
  }
  if (!setup.setupStateKnown) {
    // Tras autenticar una cuenta sin caché, el perfil tarda un instante en
    // resolverse. Mantener /auth durante esa espera evita montar MainScreen
    // (Discovery) antes de saber si hay que iniciar el onboarding.
    if (location == '/auth') return null;
    if (location == '/terms') return home;
    if (location == '/onboarding' ||
        location == '/username-setup' ||
        location == '/photo-setup' ||
        location == '/artist-select') {
      return home;
    }
    return null;
  }
  if (!setup.onboardingDone) {
    return location == '/onboarding' ? null : '/onboarding';
  }
  if (!setup.usernameSet) {
    return location == '/username-setup' ? null : '/username-setup';
  }
  if (!setup.photoSetupDone) {
    return location == '/photo-setup' ? null : '/photo-setup';
  }
  if (!setup.artistsSelected) {
    return location == '/artist-select' ? null : '/artist-select';
  }
  // Usuario listo: evitar que se quede en pantallas de setup
  if (location == '/auth' ||
      location == '/terms' ||
      location == '/onboarding' ||
      location == '/username-setup' ||
      location == '/photo-setup' ||
      location == '/artist-select') {
    return home;
  }
  // En una pantalla normal el enlace pendiente ya se ha retomado. No se borra
  // al devolverlo porque el router puede evaluar el mismo redirect varias
  // veces antes de aplicar la navegación.
  notifier._pendingProfileLink = null;
  return null;
}
