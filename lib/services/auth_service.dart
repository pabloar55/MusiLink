import 'package:firebase_auth/firebase_auth.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/user_service.dart';

/// Excepción lanzada cuando el usuario selecciona una cuenta de Google
/// distinta a la vinculada con su sesión actual.
class GoogleAccountMismatchException implements Exception {
  const GoogleAccountMismatchException();
}

/// Servicio de autenticación con Firebase Auth.
/// Soporta email+contraseña y Google Sign-In.
class AuthService {
  AuthService(
    this._userService, {
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
    required NotificationService notificationService,
  }) : _auth = auth,
       _googleSignIn = googleSignIn,
       _notificationService = notificationService;

  final UserService _userService;
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final NotificationService _notificationService;
  static Future<void>? _googleInitialization;

  Future<void> _ensureGoogleInitialized() async {
    _googleInitialization ??= _googleSignIn.initialize();
    await _googleInitialization;
  }

  /// Usuario actual de Firebase
  User? get currentUser => _auth.currentUser;

  /// Registra un nuevo usuario con email y contraseña.
  /// Crea también su perfil en Firestore.
  Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await user.updateDisplayName(displayName);
        // El perfil en Firestore se crea en UsernameSetupScreen junto con el username.
      }
      return user;
    } on FirebaseAuthException catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Inicia sesión con email y contraseña.
  /// Actualiza lastLogin en Firestore.
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await _userService.updateLastLogin(user.uid);
      }
      return user;
    } on FirebaseAuthException catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Envía un email de Firebase Auth para restablecer la contraseña.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Inicia sesión con Google.
  /// Si es la primera vez, crea el perfil en Firestore.
  Future<User?> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();

      final lightweightAttempt = _googleSignIn
          .attemptLightweightAuthentication();
      final googleUser =
          await lightweightAttempt ??
          (_googleSignIn.supportsAuthenticate()
              ? await _googleSignIn.authenticate()
              : null);

      if (googleUser == null) return null; // Usuario canceló

      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final exists = await _userService.userExists(user.uid);
        if (exists) {
          await _userService.updateLastLogin(user.uid);
        }
        // New Google users: no profile created here.
        // UsernameSetupScreen handles profile creation after they pick a username.
      }
      return user;
    } on FirebaseAuthException catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) rethrow;
      await reportError(e, StackTrace.current);
      rethrow;
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Cierra sesión de Firebase y Google.
  /// Limpia el FCM token antes de cerrar sesión.
  Future<void> signOut() async {
    await _ensureGoogleInitialized();
    try {
      await _notificationService.clearToken();
    } catch (e, st) {
      await reportError(e, st);
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Re-autentica con Google. Devuelve `false` si el usuario cancela
  /// o selecciona una cuenta diferente a la actualmente registrada.
  Future<bool> reauthenticateWithGoogle() async {
    await _ensureGoogleInitialized();
    try {
      final googleUser = _googleSignIn.supportsAuthenticate()
          ? await _googleSignIn.authenticate()
          : await _googleSignIn.attemptLightweightAuthentication();
      if (googleUser == null) return false;

      // Verificar que la cuenta seleccionada coincide con la actual
      // ANTES de llamar a Firebase para evitar registrar una cuenta distinta.
      if (googleUser.email != _auth.currentUser?.email) {
        // Limpiar el estado de Google Sign-In (quedó apuntando a la cuenta
        // incorrecta) sin afectar la sesión de Firebase Auth del usuario real.
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        throw const GoogleAccountMismatchException();
      }

      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await _auth.currentUser!.reauthenticateWithCredential(credential);
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      await reportError(e, StackTrace.current);
      rethrow;
    } on FirebaseAuthException catch (e, st) {
      await reportError(e, st);
      rethrow;
    }
  }

  /// Re-autentica con email y contraseña.
  /// Lanza [FirebaseAuthException] si las credenciales son incorrectas.
  Future<void> reauthenticateWithPassword(String email, String password) async {
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await _auth.currentUser!.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e, st) {
      await reportError(e, st);
      rethrow;
    }
  }
}
