import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';

/// Dialogo que muestra un indicador de progreso y un mensaje localizado "Signing out…".  
class SigningOutDialog extends StatelessWidget {
  const SigningOutDialog({super.key});

  // Metodo para mostrar el dialogo
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SigningOutDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.signingOut,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
