import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/utils/notification_navigation.dart';
import 'package:musi_link/widgets/user_avatar_button.dart';
import 'package:musi_link/screens/discover_screen.dart';
import 'package:musi_link/screens/messages_screen.dart';
import 'package:musi_link/screens/stats_screen.dart';
import 'package:musi_link/screens/friends_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key, this.initialPageIndex = 0});

  final int initialPageIndex;

  static int pageIndexForTab(String? tab) {
    return switch (tab) {
      'stats' => 1,
      'messages' => 2,
      'friends' => 3,
      _ => 0,
    };
  }

  static String? tabForPageIndex(int index) {
    return switch (index) {
      1 => 'stats',
      2 => 'messages',
      3 => 'friends',
      _ => null,
    };
  }

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  late int currentPageIndex;
  late final PageController _pageController;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  final List<Widget> screens = [
    const DiscoverScreen(),
    const StatsScreen(),
    const MessagesScreen(),
    const FriendsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    currentPageIndex = widget.initialPageIndex.clamp(0, screens.length - 1);
    _pageController = PageController(initialPage: currentPageIndex);
    WidgetsBinding.instance.addObserver(this);
    // Initialize FCM: permisos, token, canal Android, listeners
    ref.read(notificationServiceProvider).initialize();
    // FCM: app abierta desde notificación en background
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      if (!mounted) return;
      handleNotificationNavigation(message.data, context);
    });
  }

  @override
  void didUpdateWidget(covariant MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = widget.initialPageIndex.clamp(0, screens.length - 1);
    if (nextIndex == currentPageIndex) return;
    currentPageIndex = nextIndex;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(nextIndex);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationServiceProvider).saveTokenIfGranted();
    }
  }

  void _syncLocationToPage(int index) {
    final tab = MainScreen.tabForPageIndex(index);
    context.go(
      Uri(
        path: '/',
        queryParameters: tab == null ? null : {'tab': tab},
      ).toString(),
    );
  }

  void _selectPage(int index) {
    _pageController.jumpToPage(index);
    setState(() {
      currentPageIndex = index;
    });
    _syncLocationToPage(index);
  }

  bool get _usesCupertinoTabBar {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageOpenedSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // FCM: tap en local notification (foreground) o cold-start
    ref.listen<Map<String, dynamic>?>(pendingNotificationProvider, (_, data) {
      if (data != null) {
        handleNotificationNavigation(data, context);
        ref.read(pendingNotificationProvider.notifier).setValue(null);
      }
    });

    final unreadChats = ref.watch(unreadChatsCountProvider);
    final pendingCount = ref
        .watch(receivedRequestsProvider)
        .maybeWhen(data: (list) => list.length, orElse: () => 0);

    final bottomNavigationBar = _usesCupertinoTabBar
        ? _CupertinoMainTabBar(
            currentIndex: currentPageIndex,
            unreadChats: unreadChats,
            pendingCount: pendingCount,
            onTap: _selectPage,
            discoverLabel: l10n.navDiscover,
            statsLabel: l10n.navStats,
            messagesLabel: l10n.navMessages,
            friendsLabel: l10n.navFriends,
          )
        : TooltipVisibility(
            visible: false,
            child: NavigationBar(
              height: kIsWeb ? 72 : null,
              destinations: [
                NavigationDestination(
                  icon: const Icon(LucideIcons.compass500),
                  label: l10n.navDiscover,
                ),
                NavigationDestination(
                  icon: const Icon(LucideIcons.crown),
                  label: l10n.navStats,
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: unreadChats > 0,
                    label: unreadChats > 9
                        ? const Text('9+')
                        : Text('$unreadChats'),
                    child: const Icon(LucideIcons.messageCircle500),
                  ),
                  label: l10n.navMessages,
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: pendingCount > 0,
                    label: pendingCount > 9
                        ? const Text('9+')
                        : Text('$pendingCount'),
                    child: const Icon(LucideIcons.users500),
                  ),
                  label: l10n.navFriends,
                ),
              ],
              selectedIndex: currentPageIndex,
              onDestinationSelected: _selectPage,
            ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Image.asset('assets/images/logo.png', width: 150),
        actions: const [UserAvatarButton()],
      ),

      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            currentPageIndex = index;
          });
          _syncLocationToPage(index);
        },
        children: screens,
      ),

      bottomNavigationBar: kIsWeb
          ? _WebBottomNavigationSafeArea(child: bottomNavigationBar)
          : bottomNavigationBar,
    );
  }
}

class _WebBottomNavigationSafeArea extends StatelessWidget {
  const _WebBottomNavigationSafeArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.only(
          left: math.max(padding.left, 8),
          right: math.max(padding.right, 8),
          bottom: math.max(padding.bottom, 12),
        ),
        child: child,
      ),
    );
  }
}

class _CupertinoMainTabBar extends StatelessWidget {
  const _CupertinoMainTabBar({
    required this.currentIndex,
    required this.unreadChats,
    required this.pendingCount,
    required this.onTap,
    required this.discoverLabel,
    required this.statsLabel,
    required this.messagesLabel,
    required this.friendsLabel,
  });

  final int currentIndex;
  final int unreadChats;
  final int pendingCount;
  final ValueChanged<int> onTap;
  final String discoverLabel;
  final String statsLabel;
  final String messagesLabel;
  final String friendsLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CupertinoTabBar(
      currentIndex: currentIndex,
      onTap: onTap,
      activeColor: cs.primary,
      inactiveColor: cs.onSurfaceVariant,
      iconSize: 24,
      backgroundColor: cs.surface,
      border: Border(top: BorderSide(color: cs.outlineVariant)),
      items: [
        BottomNavigationBarItem(
          icon: const Icon(LucideIcons.compass500),
          label: discoverLabel,
        ),
        BottomNavigationBarItem(
          icon: const Icon(LucideIcons.crown),
          label: statsLabel,
        ),
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: unreadChats > 0,
            label: unreadChats > 9 ? const Text('9+') : Text('$unreadChats'),
            child: const Icon(LucideIcons.messageCircle500),
          ),
          label: messagesLabel,
        ),
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: pendingCount > 0,
            label: pendingCount > 9 ? const Text('9+') : Text('$pendingCount'),
            child: const Icon(LucideIcons.users500),
          ),
          label: friendsLabel,
        ),
      ],
    );
  }
}
