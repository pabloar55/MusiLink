import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/providers/service_providers.dart';

/// Pantalla de autenticación con Firebase.
/// Permite login/registro con email+contraseña y Google Sign-In.
/// El username se elige siempre en UsernameSetupScreen tras el registro.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isEmailLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  bool get _isLoading => _isEmailLoading || _isGoogleLoading;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isEmailLoading = true);
    try {
      User? user;
      if (_isLogin) {
        user = await ref
            .read(authServiceProvider)
            .signInWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      } else {
        user = await ref
            .read(authServiceProvider)
            .registerWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              displayName: _nameController.text.trim(),
            );
      }

      if (user == null && mounted) {
        _showError(AppLocalizations.of(context)!.authErrorCouldNotAuth);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError(_mapFirebaseError(e.code));
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context)!.authErrorUnexpected);
      }
    } finally {
      if (mounted) setState(() => _isEmailLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await ref.read(authServiceProvider).signInWithGoogle();
      if (user == null && mounted) {
        return;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError(_mapFirebaseError(e.code));
    } on GoogleSignInException catch (e) {
      if (!mounted || e.code == GoogleSignInExceptionCode.canceled) return;
      _showError(AppLocalizations.of(context)!.authErrorGoogleSignInGeneric);
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context)!.authErrorGoogleSignInGeneric);
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showError(l10n.authEnterEmail);
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      _showError(l10n.authInvalidEmail);
      return;
    }

    setState(() => _isEmailLoading = true);
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
      if (mounted) _showError(l10n.authPasswordResetSent);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') {
        _showError(l10n.authPasswordResetSent);
      } else {
        _showError(_mapFirebaseError(e.code));
      }
    } catch (_) {
      if (mounted) _showError(l10n.authErrorUnexpected);
    } finally {
      if (mounted) setState(() => _isEmailLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _mapFirebaseError(String code) {
    final l10n = AppLocalizations.of(context)!;
    switch (code) {
      case 'email-already-in-use':
        return l10n.authErrorEmailInUse;
      case 'invalid-email':
        return l10n.authErrorInvalidEmail;
      case 'weak-password':
        return l10n.authErrorWeakPassword;
      case 'user-not-found':
        return l10n.authErrorUserNotFound;
      case 'wrong-password':
        return l10n.authErrorWrongPassword;
      case 'invalid-credential':
        return l10n.authErrorInvalidCredential;
      case 'too-many-requests':
        return l10n.authErrorTooManyRequests;
      case 'account-exists-with-different-credential':
        return l10n.authErrorAccountExistsWithDifferentCredential;
      default:
        return l10n.authErrorGeneric(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', width: 250),
                const SizedBox(height: 12),
                Text(
                  l10n.authTagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),

                // Formulario
                Form(
                  key:
                      _formKey, // Asociamos el formulario a la clave para hacer referencia desde fuera de la clase
                  child: Column(
                    children: [
                      // Nombre (solo en registro)
                      if (!_isLogin)
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l10n.authName,
                            prefixIcon: const Icon(LucideIcons.circleUser),
                          ),
                          validator: (value) {
                            if (!_isLogin &&
                                (value == null || value.trim().isEmpty)) {
                              return l10n.authEnterName;
                            }
                            return null;
                          },
                        ),
                      if (!_isLogin) const SizedBox(height: 16),

                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.authEmail,
                          prefixIcon: const Icon(LucideIcons.mail),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return l10n.authEnterEmail;
                          if (!_emailRegex.hasMatch(email)) {
                            return l10n.authInvalidEmail;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Contraseña
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: l10n.authPassword,
                          prefixIcon: const Icon(LucideIcons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.authEnterPassword;
                          }
                          if (!_isLogin && value.length < 6) {
                            return l10n.authMinChars;
                          }
                          return null;
                        },
                      ),
                      if (_isLogin) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : _sendPasswordResetEmail,
                            child: Text(l10n.authForgotPassword),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ] else
                        const SizedBox(height: 24),

                      // Botón principal
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submitEmailForm,
                          child: _isEmailLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isLogin
                                      ? l10n.authSignIn
                                      : l10n.authCreateAccount,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.authOr,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),

                // Google Sign-In
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FaIcon(FontAwesomeIcons.google, size: 20),
                            const SizedBox(width: 8),
                            Text(l10n.authContinueGoogle),
                          ],
                        ),
                        if (_isGoogleLoading)
                          Positioned(
                            right: 0,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Toggle login/registro
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isLogin ? l10n.authNoAccount : l10n.authHaveAccount),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() => _isLogin = !_isLogin);
                              _formKey.currentState?.reset();
                            },
                      child: Text(
                        _isLogin ? l10n.authRegister : l10n.authLogin,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
