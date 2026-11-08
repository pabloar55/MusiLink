import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/widgets/discover/people_tab.dart';
import 'package:musi_link/widgets/discover/daily_song_tab.dart';
import 'package:musi_link/widgets/releases/weekly_releases_view.dart';

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
  bool _discoveryRequested = false;
  String? _lastRequestedTab;

  static const _peopleTabIndex = 2;

  /// Pestaña interna que abren los enlaces `/?tab=…` (notificaciones).
  static int? _tabIndexFor(String? tab) => switch (tab) {
    'daily-song' => 0,
    'releases' => 1,
    _ => null,
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_loadDiscoveryWhenSelected);
  }

  void _loadDiscoveryWhenSelected() {
    if (_tabController.index != _peopleTabIndex || _discoveryRequested) return;
    _discoveryRequested = true;
    ref.read(discoverProvider.notifier).loadDiscovery();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requestedTab = GoRouterState.of(context).uri.queryParameters['tab'];
    if (requestedTab == _lastRequestedTab) return;
    _lastRequestedTab = requestedTab;
    final index = _tabIndexFor(requestedTab);
    if (index == null || _tabController.index == index) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabController.animateTo(index);
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_loadDiscoveryWhenSelected);
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
          // Centradas a su ancho; se desplazan si no caben (p. ej., en griego).
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: [
            Tab(text: l10n.dailySongTitle),
            Tab(text: l10n.discoverTabReleases),
            Tab(text: l10n.discoverTabPeople),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              const DailySongTab(),
              const WeeklyReleasesView(),
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
            ],
          ),
        ),
      ],
    );
  }
}
