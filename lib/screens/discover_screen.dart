import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/widgets/discover/people_tab.dart';
import 'package:musi_link/widgets/discover/daily_song_tab.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with
        AutomaticKeepAliveClientMixin<DiscoverScreen>,
        TickerProviderStateMixin {
  late TabController _tabController;
  String? _lastRequestedTab;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoverProvider.notifier).loadDiscovery();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requestedTab = GoRouterState.of(context).uri.queryParameters['tab'];
    if (requestedTab == _lastRequestedTab) return;
    _lastRequestedTab = requestedTab;
    if (requestedTab != 'daily-song' || _tabController.index == 1) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabController.animateTo(1);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final discoverState = ref.watch(discoverProvider);
    final discoverNotifier = ref.read(discoverProvider.notifier);

    return Column(
      children: [
        TabBar(
          splashFactory: NoSplash.splashFactory,
          dividerColor: Colors.transparent,
          controller: _tabController,
          tabs: [
            Tab(text: l10n.discoverTabPeople),
            Tab(text: l10n.dailySongTitle),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              PeopleTab(
                results: discoverState.results,
                isLoading: discoverState.isLoading,
                isLoadingMore: discoverState.isLoadingMore,
                hasMore: discoverState.hasMore,
                hasError: discoverState.hasError,
                isStale: discoverState.isStale,
                onRefresh: discoverNotifier.refresh,
                onLoadMore: discoverNotifier.loadMore,
              ),
              const DailySongTab(),
            ],
          ),
        ),
      ],
    );
  }
}
