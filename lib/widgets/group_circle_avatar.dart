import 'dart:typed_data';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

/// CircleAvatar del grupo con su foto + fallback de icono genérico.
class GroupCircleAvatar extends StatelessWidget {
  final String photoUrl;
  final double radius;

  /// Vista previa de una foto recién elegida, aún sin publicar.
  final Uint8List? localBytes;

  const GroupCircleAvatar({
    super.key,
    required this.photoUrl,
    this.localBytes,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = localBytes;
    return CircleAvatar(
      radius: radius,
      child: ClipOval(
        child: SizedBox.expand(
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover)
              : UserProfilePhoto(
                  photoUrl: photoUrl,
                  fallback: Center(
                    child: Icon(Icons.group, size: radius * 1.25),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Avatar del grupo que abre el selector de foto al pulsarlo.
class GroupPhotoButton extends StatelessWidget {
  final String photoUrl;
  final Uint8List? localBytes;
  final double radius;
  final String tooltip;
  final bool isUploading;

  /// Insignia de cámara; se oculta cuando el avatar es demasiado pequeño.
  final bool showBadge;
  final VoidCallback? onTap;

  const GroupPhotoButton({
    super.key,
    this.photoUrl = '',
    this.localBytes,
    this.radius = 40,
    required this.tooltip,
    this.isUploading = false,
    this.showBadge = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: isUploading ? null : onTap,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            // El tamaño fijo evita la transición implícita de CircleAvatar
            // cuando el radio cambia en cada fotograma.
            SizedBox.square(
              dimension: radius * 2,
              child: GroupCircleAvatar(
                photoUrl: photoUrl,
                localBytes: localBytes,
                radius: radius,
              ),
            ),
            if (isUploading)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              )
            else if (showBadge)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
                child: Icon(
                  LucideIcons.camera,
                  size: 14,
                  color: colorScheme.onPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
