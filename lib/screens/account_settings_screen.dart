import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/notification_prefs_provider.dart';
import 'package:musi_link/providers/theme_provider.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/session_cleanup.dart';
import 'package:musi_link/services/auth_service.dart';
import 'package:musi_link/widgets/delete_account_dialog.dart';
import 'package:musi_link/widgets/image_source_picker.dart';
import 'package:musi_link/widgets/deleting_account_dialog.dart';
import 'package:musi_link/widgets/reauth_password_dialog.dart';
import 'package:musi_link/widgets/signing_out_dialog.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _isUploadingPhoto = false;

  Future<void> _goToProfile() async {
    final appUser = ref.read(currentUserProvider).asData?.value;
    if (appUser != null && mounted) {
      unawaited(context.push('/profile', extra: appUser));
    }
  }

  Future<void> _changePhoto() async {
    final l10n = AppLocalizations.of(context)!;

    final source = await showImageSourcePicker(context);
    if (source == null || !mounted) return;

    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final uid = ref.read(firebaseAuthProvider).currentUser!.uid;
      final url = await ref
          .read(storageServiceProvider)
          .uploadProfilePhoto(uid, image);
      if (url != null && mounted) {
        await ref.read(userServiceProvider).updateProfile(uid, photoUrl: url);
      }
    } catch (e, st) {
      reportError(e, st).ignore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.photoSetupError),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<String> _sendCurrentUserPasswordResetEmail(User firebaseUser) async {
    final l10n = AppLocalizations.of(context)!;
    final email = firebaseUser.email;
    if (email == null || email.trim().isEmpty) {
      return l10n.genericError;
    }

    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
      return l10n.authPasswordResetSent;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return l10n.authPasswordResetSent;
      if (e.code == 'invalid-email') return l10n.authErrorInvalidEmail;
      if (e.code == 'too-many-requests') return l10n.authErrorTooManyRequests;
      return l10n.genericError;
    } catch (e, st) {
      reportError(e, st).ignore();
      return l10n.genericError;
    }
  }

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;

    // 1. Confirmación
    final confirm = await showDeleteAccountDialog(context);
    if (confirm != true || !mounted) return;

    final firebaseUser = ref.read(firebaseAuthProvider).currentUser;
    if (firebaseUser == null) return;

    final isGoogle = firebaseUser.providerData.any(
      (p) => p.providerId == 'google.com',
    );

    // 2. Re-autenticación antes de tocar nada
    if (isGoogle) {
      bool success;
      try {
        success = await ref
            .read(authServiceProvider)
            .reauthenticateWithGoogle();
      } on GoogleAccountMismatchException {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.reauthWrongAccount)));
        return;
      } catch (e, st) {
        reportError(e, st).ignore();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.genericError)));
        return;
      }
      if (!success || !mounted) return; // usuario canceló
    } else {
      final password = await showReauthPasswordDialog(
        context,
        onForgotPassword: () =>
            _sendCurrentUserPasswordResetEmail(firebaseUser),
      );
      if (password == null || !mounted) return; // usuario canceló
      try {
        await ref
            .read(authServiceProvider)
            .reauthenticateWithPassword(firebaseUser.email ?? '', password);
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? l10n.authErrorWrongPassword
            : l10n.genericError;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }

    if (!mounted) return;

    // 3. Progreso — a partir de aquí no hay marcha atrás
    DeletingAccountDialog.show(context);

    final uid = firebaseUser.uid;

    try {
      // 4. Datos de Firestore (user aún autenticado → reglas OK)
      await ref.read(friendServiceProvider).deleteAllUserFriendData(uid);
      await ref.read(chatServiceProvider).deleteAllUserChatData(uid);
      await ref.read(storageServiceProvider).deleteProfilePhoto(uid);
      await ref.read(userServiceProvider).anonymizeUser(uid);

      // 5. Capturar servicios antes de borrar (delete() desmonta el widget)
      final authService = ref.read(authServiceProvider);
      final chatService = ref.read(chatServiceProvider);
      final musicProfileService = ref.read(musicProfileServiceProvider);

      await firebaseUser.delete();

      // 7. Limpiar sesión Google + cachés
      try {
        await authService.signOut();
      } catch (_) {}
      chatService.clearCache();
      musicProfileService.clearCache();
      if (mounted) clearSessionState(ref);

      if (!mounted) return;
      Navigator.of(context).pop();
      context.go('/auth');
    } catch (e, st) {
      reportError(e, st).ignore();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.genericError)));
    }
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    SigningOutDialog.show(context);
    final authService = ref.read(authServiceProvider);
    final chatService = ref.read(chatServiceProvider);
    try {
      await authService.signOut();
    } catch (e, st) {
      reportError(e, st).ignore();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.genericError)),
      );
      return;
    }
    chatService.clearCache();
    ref.read(musicProfileServiceProvider).clearCache();
    clearSessionState(ref);
    if (!mounted) return;
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDarkMode = ref.watch(isDarkProvider);
    final vibrationEnabled = ref.watch(vibrationEnabledProvider);
    final soundEnabled = ref.watch(soundEnabledProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Builder(
        builder: (context) {
          final appUser = ref.watch(currentUserProvider).asData?.value;
          final firebaseUser = ref.read(firebaseAuthProvider).currentUser;
          final imageUrl = appUser?.photoUrl ?? '';
          final displayName = appUser?.displayName ?? l10n.socialUser;
          final email = firebaseUser?.email ?? '';

          final bottomInset = MediaQuery.paddingOf(context).bottom;
          return ListView(
            padding: EdgeInsets.only(
              left: AppTokens.spaceLG,
              right: AppTokens.spaceLG,
              top: AppTokens.spaceXL,
              bottom: AppTokens.spaceMD + bottomInset,
            ),
            children: [
              // ── Profile header ─────────────────────────────────────
              _ProfileCard(
                imageUrl: imageUrl,
                displayName: displayName,
                email: email,
                uid: appUser?.uid ?? firebaseUser?.uid ?? '',
                onTap: _goToProfile,
                onAvatarTap: _changePhoto,
                isUploadingPhoto: _isUploadingPhoto,
              ),

              const SizedBox(height: AppTokens.spaceXL),

              // ── Appearance ─────────────────────────────────────────
              _SectionHeader(label: l10n.settingsAppearance),
              const SizedBox(height: AppTokens.spaceSM),
              _SettingsCard(
                children: [
                  _SwitchTile(
                    icon: LucideIcons.moon,
                    label: l10n.menuDarkMode,
                    value: isDarkMode,
                    onChanged: (_) =>
                        ref.read(themeModeProvider.notifier).toggleDarkLight(),
                  ),
                ],
              ),

              const SizedBox(height: AppTokens.spaceLG),

              // ── Notifications ──────────────────────────────────────
              _SectionHeader(label: l10n.settingsNotifications),
              const SizedBox(height: AppTokens.spaceSM),
              _SettingsCard(
                children: [
                  _SwitchTile(
                    icon: LucideIcons.volume2,
                    label: l10n.settingsSound,
                    value: soundEnabled,
                    onChanged: (_) =>
                        ref.read(soundEnabledProvider.notifier).toggle(),
                  ),
                  _SwitchTile(
                    icon: LucideIcons.vibrate,
                    label: l10n.settingsVibration,
                    value: vibrationEnabled,
                    onChanged: (_) =>
                        ref.read(vibrationEnabledProvider.notifier).toggle(),
                  ),
                ],
              ),

              const SizedBox(height: AppTokens.spaceLG),

              // ── Privacy ───────────────────────────────────────────
              _SectionHeader(label: l10n.settingsPrivacy),
              const SizedBox(height: AppTokens.spaceSM),
              _SettingsCard(
                children: [
                  _ChevronTile(
                    icon: LucideIcons.userX,
                    label: l10n.settingsBlockedUsers,
                    onTap: () => context.push('/blocked-users'),
                  ),
                ],
              ),

              const SizedBox(height: AppTokens.spaceLG),

              // ── Legal ──────────────────────────────────────────────
              _SectionHeader(label: l10n.settingsLegal),
              const SizedBox(height: AppTokens.spaceSM),
              _SettingsCard(
                children: [
                  _ChevronTile(
                    icon: LucideIcons.shieldCheck,
                    label: l10n.settingsPrivacyPolicy,
                    onTap: () => context.push('/privacy-policy'),
                  ),
                ],
              ),

              const SizedBox(height: AppTokens.space2XL),

              // ── Sign out ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(LucideIcons.logOut),
                  label: Text(l10n.menuSignOut),
                ),
              ),

              const SizedBox(height: AppTokens.spaceMD),

              // ── Delete account ─────────────────────────────────────
              Center(
                child: TextButton.icon(
                  onPressed: _deleteAccount,
                  icon: Icon(LucideIcons.trash2, size: 16, color: cs.error),
                  label: Text(
                    l10n.settingsDeleteAccount,
                    style: TextStyle(color: cs.error),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String imageUrl;
  final String displayName;
  final String email;
  final String uid;
  final VoidCallback onTap;
  final VoidCallback onAvatarTap;
  final bool isUploadingPhoto;

  const _ProfileCard({
    required this.imageUrl,
    required this.displayName,
    required this.email,
    required this.uid,
    required this.onTap,
    required this.onAvatarTap,
    required this.isUploadingPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLG),
          child: Row(
            children: [
              GestureDetector(
                onTap: isUploadingPhoto ? null : onAvatarTap,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: cs.surfaceContainerHighest,
                      child: isUploadingPhoto
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ClipOval(
                              child: SizedBox.expand(
                                child: UserProfilePhoto(
                                  photoUrl: imageUrl,
                                  fallback: Icon(
                                    LucideIcons.user,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (!isUploadingPhoto)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 1.5),
                        ),
                        child: Icon(
                          LucideIcons.camera,
                          size: 10,
                          color: cs.onPrimary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.spaceLG),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.spaceXS),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: cs.onSurfaceVariant,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppTokens.spaceXS),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(
                height: 1,
                indent: AppTokens.spaceLG + 22 + AppTokens.spaceMD,
              ),
          ],
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: Icon(icon, size: 22, color: cs.onSurfaceVariant),
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS,
      ),
    );
  }
}

class _ChevronTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ChevronTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, size: 22, color: cs.onSurfaceVariant),
      title: Text(label),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: cs.onSurfaceVariant,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS,
      ),
    );
  }
}
