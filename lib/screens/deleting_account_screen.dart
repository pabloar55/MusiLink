import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/session_cleanup.dart';

class DeletingAccountScreen extends ConsumerStatefulWidget {
  const DeletingAccountScreen({super.key});

  @override
  ConsumerState<DeletingAccountScreen> createState() =>
      _DeletingAccountScreenState();
}

class _DeletingAccountScreenState extends ConsumerState<DeletingAccountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeDeletion());
  }

  Future<void> _resumeDeletion() async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) {
      if (mounted) context.go('/auth?accountDeletion=pending');
      return;
    }

    final deletionService = ref.read(accountDeletionServiceProvider);
    final authService = ref.read(authServiceProvider);
    try {
      // Idempotente: también reencola un job detenido en retry_wait. No se
      // espera a que termine; el backend continúa sin una sesión cliente.
      await deletionService.requestDeletion();
    } catch (error, stack) {
      reportError(error, stack).ignore();
    }

    if (!mounted) return;
    final router = GoRouter.of(context);
    clearSessionState(ref);
    try {
      await authService.signOut(clearNotificationToken: false);
    } catch (error, stack) {
      reportError(error, stack).ignore();
      try {
        await ref.read(firebaseAuthProvider).signOut();
      } catch (_) {}
    }
    router.go('/auth?accountDeletion=pending');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PopScope(
        canPop: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.deletingAccount,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
