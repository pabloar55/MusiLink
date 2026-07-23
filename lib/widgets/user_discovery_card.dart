import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

class UserDiscoveryCard extends StatelessWidget {
  final DiscoveryResult result;
  final VoidCallback onTap;

  const UserDiscoveryCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = result.user;
    final score = result.score.round();
    final isHighScore = score >= 70;
    final isMediumScore = score >= 40;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLG,
        vertical: AppTokens.spaceXS,
      ),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent stripe
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isHighScore
                          ? [AppTokens.spotifyGreen, AppTokens.spotifyGreenDark]
                          : isMediumScore
                          ? [cs.secondary, cs.secondary.withAlpha(180)]
                          : [cs.outline, cs.outlineVariant],
                    ),
                  ),
                ),
                // Card content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceLG),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _UserAvatar(
                          photoUrl: user.photoUrl,
                          uid: user.uid,
                          score: score,
                        ),
                        const SizedBox(width: AppTokens.spaceMD),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      user.displayName,
                                      style: tt.titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  _ScoreBadge(score: score, colorScheme: cs),
                                  const SizedBox(width: AppTokens.spaceXS),
                                  Icon(
                                    LucideIcons.chevronRight,
                                    color: cs.onSurfaceVariant,
                                    size: 18,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppTokens.spaceXS),

                              if (result.user.topArtistNames.isNotEmpty ||
                                  result.sharedArtistNames.isNotEmpty)
                                _MetaRow(
                                  icon: LucideIcons.music,
                                  sharedArtists: result.sharedArtistNames,
                                  allArtists: result.user.topArtistNames,
                                  colorScheme: cs,
                                  textTheme: tt,
                                ),

                              if (result.sharedGenreNames.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _GenreRow(
                                  genres: result.sharedGenreNames,
                                  colorScheme: cs,
                                  textTheme: tt,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final String photoUrl;
  final String uid;
  final int score;
  const _UserAvatar({
    required this.photoUrl,
    required this.uid,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHighScore = score >= 70;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isHighScore ? AppTokens.spotifyGreen : cs.outline,
          width: isHighScore ? 2.5 : 1.5,
        ),
        boxShadow: isHighScore
            ? [
                BoxShadow(
                  color: AppTokens.spotifyGreen.withAlpha(80),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: UserProfilePhoto(
          photoUrl: photoUrl,
          fallback: ColoredBox(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(
                LucideIcons.user,
                size: 26,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  final ColorScheme colorScheme;
  const _ScoreBadge({required this.score, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final isHigh = score >= 70;
    final isMedium = score >= 40;
    final color = isHigh
        ? AppTokens.spotifyGreen
        : (isMedium ? cs.secondary : cs.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isHigh
            ? AppTokens.spotifyGreen.withAlpha(30)
            : color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        border: Border.all(
          color: isHigh
              ? AppTokens.spotifyGreen.withAlpha(160)
              : color.withAlpha(80),
          width: 1.5,
        ),
      ),
      child: Text(
        '$score%',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final List<String> sharedArtists;
  final List<String> allArtists;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _MetaRow({
    required this.icon,
    required this.sharedArtists,
    required this.allArtists,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final sharedSet = sharedArtists.map((a) => a.toLowerCase()).toSet();
    final visibleSharedArtists = sharedArtists.take(5).toList();
    final extrasCount = 5 - visibleSharedArtists.length;
    final extras = allArtists
        .where((a) => !sharedSet.contains(a.toLowerCase()))
        .take(extrasCount)
        .toList();
    final artists = [...visibleSharedArtists, ...extras];

    return Row(
      children: [
        Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: AppTokens.spaceXS),
        Expanded(
          child: _FadingScroll(
            child: Row(
              children: artists.map((artist) {
                final isShared = sharedSet.contains(artist.toLowerCase());
                if (isShared) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTokens.spotifyGreen.withAlpha(30),
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusFull,
                        ),
                      ),
                      child: Text(
                        artist,
                        style: textTheme.labelSmall?.copyWith(
                          color: AppTokens.spotifyGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    artist,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _FadingScroll extends StatelessWidget {
  final Widget child;
  const _FadingScroll({required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: child,
      ),
    );
  }
}

class _GenreRow extends StatelessWidget {
  final List<String> genres;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _GenreRow({
    required this.genres,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return Row(
      children: [
        Icon(LucideIcons.tag, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: AppTokens.spaceXS),
        Expanded(
          child: _FadingScroll(
            child: Row(
              children: genres
                  .take(3)
                  .map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(22),
                          borderRadius: BorderRadius.circular(
                            AppTokens.radiusFull,
                          ),
                        ),
                        child: Text(
                          g,
                          style: textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}
