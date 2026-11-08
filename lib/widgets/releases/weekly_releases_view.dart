import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/artist_release.dart';
import 'package:musi_link/providers/artist_releases_provider.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:musi_link/widgets/track_artwork.dart';
import 'package:url_launcher/url_launcher.dart';

/// Singles y álbumes de la semana de los artistas seguidos, en tarjetas.
class WeeklyReleasesView extends ConsumerWidget {
  const WeeklyReleasesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final releases = ref.watch(weeklyReleasesProvider);

    Future<void> refresh() => ref
        .refresh(weeklyReleasesProvider.future)
        .then((_) {}, onError: (_) {});

    return releases.when(
      skipLoadingOnRefresh: true,
      loading: () => const _ReleaseGridSkeleton(),
      error: (error, stack) => _ReleasesMessage(
        icon: LucideIcons.cloudOff,
        title: l10n.genericError,
        onRefresh: refresh,
        action: TextButton(
          onPressed: () => ref.invalidate(weeklyReleasesProvider),
          child: Text(l10n.dailySongRetry),
        ),
      ),
      data: (items) => items.isEmpty
          ? _ReleasesMessage(
              icon: LucideIcons.disc3,
              title: l10n.releasesEmpty,
              subtitle: l10n.releasesHint,
              onRefresh: refresh,
            )
          : RefreshIndicator.adaptive(
              onRefresh: refresh,
              child: _ReleaseGrid(
                itemCount: items.length,
                itemBuilder: (_, index) => ReleaseCard(release: items[index]),
              ),
            ),
    );
  }
}

class _ReleaseGrid extends StatelessWidget {
  const _ReleaseGrid({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  static const _maxTileWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppTokens.spaceMD;
        final available = constraints.maxWidth - AppTokens.spaceLG * 2;
        final columns = ((available + spacing) / (_maxTileWidth + spacing))
            .ceil()
            .clamp(2, 6);
        final tileWidth = (available - spacing * (columns - 1)) / columns;
        // Portada cuadrada y tres líneas de texto.
        final textHeight =
            textScaler.scale(14) * 1.4 + textScaler.scale(12) * 2.8;
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppTokens.spaceLG,
            AppTokens.spaceSM,
            AppTokens.spaceLG,
            AppTokens.spaceLG + bottomInset,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: AppTokens.spaceLG,
            mainAxisExtent: tileWidth + AppTokens.spaceSM + textHeight,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// Tarjeta de un lanzamiento; al pulsarla se abre en Spotify.
class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.release});

  final ArtistRelease release;

  Future<void> _open() async {
    try {
      await launchUrl(release.spotifyUri, mode: LaunchMode.externalApplication);
    } catch (error, stack) {
      await reportError(error, stack);
    }
  }

  String _dateLabel(BuildContext context, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(release.releaseDate).inDays;
    if (days <= 0) return l10n.releaseToday;
    if (days == 1) return l10n.releaseYesterday;
    return MaterialLocalizations.of(context)
        .formatShortMonthDay(release.releaseDate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final type = release.type == ArtistReleaseType.album
        ? l10n.releaseTypeAlbum
        : l10n.releaseTypeSingle;
    final artists = release.artistNames.join(', ');

    return Semantics(
      button: true,
      label: '${release.name}, $artists, $type',
      excludeSemantics: true,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: TrackArtwork(
                imageUrl: release.imageUrl,
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.circular(AppTokens.radiusMD),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              release.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              artists,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            Text(
              '$type · ${_dateLabel(context, l10n)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleasesMessage extends StatelessWidget {
  const _ReleasesMessage({
    required this.icon,
    required this.title,
    required this.onRefresh,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXL),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 40, color: cs.onSurfaceVariant),
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: tt.titleSmall,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppTokens.spaceXS),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: AppTokens.spaceSM),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleaseGridSkeleton extends StatelessWidget {
  const _ReleaseGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: _ReleaseGrid(
        itemCount: 6,
        itemBuilder: (_, _) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: SkeletonBox(height: double.infinity, borderRadius: 12),
            ),
            SizedBox(height: AppTokens.spaceSM),
            SkeletonBox(width: 120),
            SizedBox(height: AppTokens.spaceXS),
            SkeletonBox(width: 80, height: 12),
          ],
        ),
      ),
    );
  }
}
