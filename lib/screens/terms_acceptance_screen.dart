import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/utils/terms_and_conditions.dart';
import 'package:url_launcher/url_launcher.dart';

class TermsAcceptanceScreen extends ConsumerStatefulWidget {
  const TermsAcceptanceScreen({super.key});

  @override
  ConsumerState<TermsAcceptanceScreen> createState() =>
      _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends ConsumerState<TermsAcceptanceScreen> {
  bool _busy = false;
  bool _accepted = false;

  Future<void> _acceptTerms() async {
    if (!_accepted || _busy) return;
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      // La callable responde únicamente después de persistir la aceptación y
      // devuelve la versión confirmada. No hace falta una segunda lectura.
      await ref.read(termsAcceptanceServiceProvider).acceptCurrentVersion();
      if (!mounted || ref.read(firebaseAuthProvider).currentUser?.uid != uid) {
        return;
      }
      ref.read(appRouterNotifierProvider).setTermsAccepted(uid);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.termsSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open $uri');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.termsOpenError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // El router solo abre esta pantalla tras confirmar que falta aceptación.
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: AlertDialog(
            title: Text(l10n.termsAcceptanceTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.termsAcceptanceIntro),
                    const SizedBox(height: 8),
                    Text(
                      l10n.termsAcceptanceVersion(TermsAndConditions.version),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () =>
                          _open(TermsAndConditions.urlForLocale(language)),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(l10n.termsOpenDocument),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _accepted,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _accepted = value ?? false),
                      title: Text(l10n.termsAcceptCheckbox),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: _accepted && !_busy ? _acceptTerms : null,
                child: _busy
                    ? Text(l10n.termsAccepting)
                    : Text(l10n.termsAcceptAndContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
