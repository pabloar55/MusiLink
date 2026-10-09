import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/router/app_router.dart';
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
  late final AppRouterNotifier _routerNotifier;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _routerNotifier = ref.read(appRouterNotifierProvider)
      ..addListener(_showSaveError);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showSaveError());
  }

  @override
  void dispose() {
    _routerNotifier.removeListener(_showSaveError);
    super.dispose();
  }

  void _acceptTerms() {
    if (!_accepted) return;
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    // El router avanza al instante; el registro se confirma en segundo plano.
    _routerNotifier.acceptTerms(uid);
  }

  /// Si el servidor rechazó el registro, el router vuelve a esta pantalla.
  void _showSaveError() {
    if (!mounted || !_routerNotifier.takeTermsSaveError()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.termsSaveError)),
    );
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
                      onChanged: (value) =>
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
                onPressed: _accepted ? _acceptTerms : null,
                child: Text(l10n.termsAcceptAndContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
