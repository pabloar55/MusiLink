import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';

Future<ImageSource?> showImageSourcePicker(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;

  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(LucideIcons.image, color: cs.onSurface),
              title: Text(l10n.photoSetupGallery),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(LucideIcons.camera, color: cs.onSurface),
              title: Text(l10n.photoSetupCamera),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    ),
  );
}
