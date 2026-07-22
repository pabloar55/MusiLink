import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:musi_link/widgets/track_artwork.dart';

class TrackSearchSheet extends ConsumerStatefulWidget {
  final ValueChanged<Track> onTrackSelected;

  const TrackSearchSheet({super.key, required this.onTrackSelected});

  @override
  ConsumerState<TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends ConsumerState<TrackSearchSheet> {
  final _searchController = TextEditingController();
  List<Track> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _loading = true);
    try {
      final results = await ref
          .read(musicCatalogServiceProvider)
          .searchTracks(query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = []);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.chatSearchSong,
                  prefixIcon: const Icon(LucideIcons.search),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: AppTheme.pillInputBorder,
                  enabledBorder: AppTheme.pillInputBorder,
                  focusedBorder: AppTheme.pillInputBorder,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            Expanded(
              child: _loading
                  ? SkeletonShimmer(
                      child: ListView.builder(
                        itemCount: 8,
                        itemBuilder: (_, _) => const SkeletonSongTile(),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? AppLocalizations.of(context)!.chatTypeToSearch
                            : AppLocalizations.of(context)!.chatNoResults,
                        style: TextStyle(
                          color: colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final track = _results[index];
                        return ListTile(
                          leading: TrackArtwork(
                            imageUrl: track.imageUrl,
                            width: 48,
                            height: 48,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => widget.onTrackSelected(track),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
