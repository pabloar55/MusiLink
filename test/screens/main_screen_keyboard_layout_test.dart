import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/friend_request.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/providers/music_profile_sync_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/screens/main_screen.dart';
import 'package:musi_link/services/music_profile_sync_coordinator.dart';
import 'package:musi_link/services/notification_service.dart';

class _TestDiscoverNotifier extends DiscoverNotifier {
  @override
  DiscoverState build() => const DiscoverState();

  @override
  Future<void> loadDiscovery({bool useLocalCache = true}) async {}
}

class _MockMusicProfileSyncCoordinator extends Mock
    implements MusicProfileSyncCoordinator {}

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  testWidgets('el teclado no redimensiona la pagina situada tras un modal', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final syncCoordinator = _MockMusicProfileSyncCoordinator();
    final notifications = _MockNotificationService();
    when(syncCoordinator.resume).thenReturn(null);
    when(notifications.saveTokenIfGranted).thenAnswer((_) async {});

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const MainScreen())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((_) => Stream<AppUser?>.value(null)),
          receivedRequestsProvider.overrideWith(
            (_) => Stream<List<FriendRequest>>.value(const []),
          ),
          unreadChatsCountProvider.overrideWithValue(0),
          discoverProvider.overrideWith(_TestDiscoverNotifier.new),
          musicProfileSyncCoordinatorProvider.overrideWithValue(
            syncCoordinator,
          ),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffoldFinder = find.byType(Scaffold);
    expect(scaffoldFinder, findsOneWidget);
    final scaffold = tester.widget<Scaffold>(scaffoldFinder);
    expect(scaffold.resizeToAvoidBottomInset, isFalse);
    final pageViewFinder = find.byWidget(scaffold.body!);
    final heightWithoutKeyboard = tester.getSize(pageViewFinder).height;

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    expect(tester.getSize(pageViewFinder).height, heightWithoutKeyboard);
  });
}
