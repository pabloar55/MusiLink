import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';

/// Muestra un diálogo de confirmación para eliminar la cuenta.
/// Devuelve `true` si el usuario confirma, `false` o `null` si cancela.
Future<bool?> showDeleteAccountDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        LucideIcons.triangleAlert,
        color: Theme.of(context).colorScheme.error,
        size: 32,
      ),
      title: Text(l10n.settingsDeleteAccount),
      content: Text(l10n.deleteAccountBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.friendsCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.deleteAccountConfirm,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
}
