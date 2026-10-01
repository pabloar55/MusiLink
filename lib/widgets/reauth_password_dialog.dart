import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';

/// Muestra un dialogo pidiendo la contrasena para re-autenticar al usuario
/// antes de eliminar su cuenta. Devuelve la contrasena introducida, o `null`
/// si el usuario cancela.
Future<String?> showReauthPasswordDialog(
  BuildContext context, {
  Future<String> Function()? onForgotPassword,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReauthPasswordDialog(onForgotPassword: onForgotPassword),
  );
}

class _ReauthPasswordDialog extends StatefulWidget {
  const _ReauthPasswordDialog({this.onForgotPassword});

  final Future<String> Function()? onForgotPassword;

  @override
  State<_ReauthPasswordDialog> createState() => _ReauthPasswordDialogState();
}

class _ReauthPasswordDialogState extends State<_ReauthPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _isSendingReset = false;
  String? _resetMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    Navigator.of(context).pop(password.isEmpty ? null : password);
  }

  Future<void> _sendPasswordReset() async {
    final onForgotPassword = widget.onForgotPassword;
    if (onForgotPassword == null || _isSendingReset) return;

    setState(() {
      _isSendingReset = true;
      _resetMessage = null;
    });

    final message = await onForgotPassword();
    if (!mounted) return;

    setState(() {
      _isSendingReset = false;
      _resetMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.reauthTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reauthBody),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.authPassword,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_resetMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _resetMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (widget.onForgotPassword != null)
          TextButton(
            onPressed: _isSendingReset ? null : _sendPasswordReset,
            child: _isSendingReset
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.authForgotPassword),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.friendsCancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.reauthConfirm)),
      ],
    );
  }
}
