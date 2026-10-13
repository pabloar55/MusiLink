import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/services/service_exceptions.dart';

/// Avisa de una operación fallida. [fallbackMessage] sustituye al error
/// genérico y [notAllowedMessage] se usa cuando el backend la deniega.
void showServiceError(
  BuildContext context,
  Object? error, {
  String? notAllowedMessage,
  String? fallbackMessage,
}) {
  final l10n = AppLocalizations.of(context)!;
  final fallback = fallbackMessage ?? l10n.genericError;
  final message = switch (error) {
    RateLimitedException() => l10n.authErrorTooManyRequests,
    NotAllowedException() => notAllowedMessage ?? fallback,
    _ => fallback,
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
