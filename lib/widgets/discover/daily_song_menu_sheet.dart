import 'package:material_ui/material_ui.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/track_artwork.dart';

typedef DailySongMenuItem = ({IconData icon, String label, VoidCallback onTap});

/// Shows the actions available for [song]. The sheet closes before the
/// selected item's callback runs, so callbacks may open another route.
Future<void> showDailySongMenu(
  BuildContext context, {
  required Track song,
  required List<DailySongMenuItem> items,
}) async {
  final selected = await showModalBottomSheet<DailySongMenuItem>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLG,
                  0,
                  AppTokens.spaceLG,
                  AppTokens.spaceMD,
                ),
                child: Row(
                  children: [
                    TrackArtwork(
                      imageUrl: song.imageUrl,
                      width: 48,
                      height: 48,
                      borderRadius: BorderRadius.circular(AppTokens.radiusSM),
                    ),
                    const SizedBox(width: AppTokens.spaceMD),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final item in items)
                ListTile(
                  leading: Icon(item.icon, color: theme.colorScheme.onSurface),
                  title: Text(item.label),
                  onTap: () => Navigator.of(sheetContext).pop(item),
                ),
              const SizedBox(height: AppTokens.spaceSM),
            ],
          ),
        ),
      );
    },
  );
  selected?.onTap();
}
