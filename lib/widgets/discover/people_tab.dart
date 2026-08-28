import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:musi_link/widgets/user_discovery_card.dart';
import 'package:musi_link/models/discovery_result.dart';

class PeopleTab extends StatefulWidget {
  final List<DiscoveryResult> results;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool hasError;
  final bool isStale;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  const PeopleTab({
    super.key,
    required this.results,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.hasError,
    this.isStale = false,
    required this.onRefresh,
    required this.onLoadMore,
  });

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (widget.isLoading) {
      return SkeletonShimmer(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          children: List.generate(4, (_) => const SkeletonDiscoveryCard()),
        ),
      );
    }

    if (widget.hasError) {
      return Center(
        child: Text(
          l10n.discoverErrorLoading,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (widget.results.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.searchX,
                      size: 64,
                      color: colorScheme.onSurfaceVariant.withAlpha(128),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.discoverNoUsers,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.discoverNoUsersHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant.withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: widget.results.length + (widget.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == widget.results.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: widget.isLoadingMore
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            );
          }
          final result = widget.results[index];
          return UserDiscoveryCard(
            result: result,
            onTap: () => context.push(
              userProfileLocation(result.user.uid),
              extra: result,
            ),
          );
        },
      ),
    );
  }
}
