import 'package:material_ui/material_ui.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

/// Foto del remitente a la izquierda de un mensaje recibido.
///
/// [MessageSenderAvatar.spacer] reserva el mismo hueco sin foto para alinear
/// los mensajes consecutivos de una misma persona.
class MessageSenderAvatar extends StatelessWidget {
  static const double radius = 14;

  /// Ancho que ocupa junto a la burbuja, incluida la separación.
  static const double extent = radius * 2 + AppTokens.spaceSM;

  final Future<AppUser?>? userFuture;
  final String fallbackName;

  const MessageSenderAvatar({
    super.key,
    required Future<AppUser?> this.userFuture,
    required this.fallbackName,
  });

  const MessageSenderAvatar.spacer({super.key})
    : userFuture = null,
      fallbackName = '';

  @override
  Widget build(BuildContext context) {
    if (userFuture == null) return const SizedBox(width: extent);
    return Padding(
      padding: const EdgeInsets.only(right: AppTokens.spaceSM),
      child: FutureBuilder<AppUser?>(
        future: userFuture,
        builder: (context, snapshot) {
          // Sin inicial provisional mientras se resuelve el perfil.
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const CircleAvatar(radius: radius);
          }
          final user = snapshot.data;
          return UserCircleAvatar(
            photoUrl: user?.photoUrl ?? '',
            name: user?.displayName ?? fallbackName,
            radius: radius,
          );
        },
      ),
    );
  }
}
