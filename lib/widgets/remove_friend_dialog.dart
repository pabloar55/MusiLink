import 'package:flutter/material.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/widgets/adaptive_confirmation_dialog.dart';

/// Muestra un diálogo de confirmación para eliminar un amigo.
/// Devuelve `true` si el usuario confirma, `false` o `null` si cancela.
Future<bool?> showRemoveFriendDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showAdaptiveConfirmationDialog(
    context: context,
    title: l10n.friendsRemove,
    content: l10n.friendsRemoveBody,
    cancelLabel: l10n.friendsCancel,
    confirmLabel: l10n.friendsRemove,
    destructive: true,
  );
}
