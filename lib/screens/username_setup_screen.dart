import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/services/user_service.dart';

class UsernameSetupScreen extends ConsumerStatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  ConsumerState<UsernameSetupScreen> createState() =>
      _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends ConsumerState<UsernameSetupScreen> {
  static final RegExp _validUsername = RegExp(r'^[a-z0-9_]{3,20}$');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _isChecking = false;
  bool? _isAvailable;
  String _lastChecked = '';
  Timer? _debounce;
  int _usernameCheckGeneration = 0;

  @override
  void initState() {
    super.initState();
    final googleName =
        ref.read(firebaseAuthProvider).currentUser?.displayName ?? '';
    _displayNameController = TextEditingController(text: googleName);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    final generation = ++_usernameCheckGeneration;
    _debounce?.cancel();
    setState(() {
      _isChecking = false;
      _isAvailable = null;
      _lastChecked = '';
    });

    if (!_validUsername.hasMatch(value)) return;

    setState(() => _isChecking = true);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      try {
        final taken = await ref.read(userServiceProvider).usernameExists(value);
        if (!mounted ||
            generation != _usernameCheckGeneration ||
            _usernameController.text != value) {
          return;
        }
        setState(() {
          _isChecking = false;
          _isAvailable = !taken;
          _lastChecked = value;
        });
      } catch (_) {
        if (mounted && generation == _usernameCheckGeneration) {
          setState(() => _isChecking = false);
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    if (_isAvailable != true || _lastChecked != username) return;

    setState(() => _isLoading = true);
    try {
      final displayName = _displayNameController.text.trim();
      final userService = ref.read(userServiceProvider);

      await userService.createUserProfile(
        displayName: displayName,
        username: username,
      );

      if (mounted) {
        ref.read(appRouterNotifierProvider).setUsernameSet();
      }
    } on UsernameAlreadyTakenException {
      if (mounted) {
        setState(() {
          _isAvailable = false;
          _lastChecked = username;
        });
        _formKey.currentState?.validate();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.authUsernameTaken),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.genericError)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final username = _usernameController.text;
    final isFormatValid = _validUsername.hasMatch(username);

    Widget? usernameSuffix;
    if (username.isNotEmpty && isFormatValid) {
      if (_isChecking) {
        usernameSuffix = const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      } else if (_isAvailable == true) {
        usernameSuffix = Icon(
          LucideIcons.circleCheck,
          color: colorScheme.primary,
        );
      } else if (_isAvailable == false) {
        usernameSuffix = Icon(LucideIcons.circleX, color: colorScheme.error);
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Icon(
                    LucideIcons.atSign,
                    size: 56,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    l10n.usernameSetupTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    l10n.usernameSetupSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 32),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Nombre editable (pre-relleno con el nombre de Google)
                      TextFormField(
                        controller: _displayNameController,
                        enabled: !_isLoading,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.authName,
                          prefixIcon: const Icon(LucideIcons.circleUser),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.authEnterName;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Username
                      TextFormField(
                        controller: _usernameController,
                        enabled: !_isLoading,
                        autofocus: false,
                        autocorrect: false,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-z0-9_]'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.authUsername,
                          hintText: l10n.authUsernameHint,
                          prefixIcon: const Icon(LucideIcons.atSign),
                          suffixIcon: usernameSuffix,
                        ),
                        onChanged: _onUsernameChanged,
                        validator: (value) {
                          final v = value ?? '';
                          if (v.length < 3) return l10n.authUsernameTooShort;
                          if (v.length > 20) return l10n.authUsernameTooLong;
                          if (!_validUsername.hasMatch(v)) {
                            return l10n.authUsernameInvalidChars;
                          }
                          if (_lastChecked == v && _isAvailable == false) {
                            return l10n.authUsernameTaken;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                if (username.isNotEmpty &&
                    isFormatValid &&
                    _isAvailable == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      l10n.authUsernameAvailable,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (username.isNotEmpty && isFormatValid && _isChecking)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      l10n.authUsernameChecking,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed:
                        _isLoading ||
                            _isChecking ||
                            _isAvailable != true ||
                            _lastChecked != username
                        ? null
                        : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.usernameSetupButton),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
