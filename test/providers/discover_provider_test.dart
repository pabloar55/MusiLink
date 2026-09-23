import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/music_profile_service.dart';

class _MockMusicProfileService extends Mock implements MusicProfileService {}

void main() {
  const blocked = DiscoveryResult(
    user: AppUser(uid: 'blocked', displayName: 'Blocked'),
    score: 50,
    sharedArtistNames: [],
    sharedGenreNames: [],
  );
  const visible = DiscoveryResult(
    user: AppUser(uid: 'visible', displayName: 'Visible'),
    score: 40,
    sharedArtistNames: [],
    sharedGenreNames: [],
  );

  late _MockMusicProfileService service;
  late ProviderContainer container;

  setUp(() {
    service = _MockMusicProfileService();
    when(() => service.hasMoreDiscoveryUsers).thenReturn(false);
    container = ProviderContainer(
      overrides: [musicProfileServiceProvider.overrideWithValue(service)],
    );
  });

  tearDown(() => container.dispose());

  test('keeps previous results when the blocked users read fails', () async {
    final notifier = container.read(discoverProvider.notifier);
    when(() => service.readStoredDiscoveryUsers())
        .thenAnswer((_) async => [blocked, visible]);
    await notifier.refresh();

    when(() => service.readStoredDiscoveryUsers())
        .thenThrow(BlockedUsersReadException(StateError('offline')));
    await notifier.refresh();

    final state = container.read(discoverProvider);
    expect(state.results, [blocked, visible]);
    expect(state.isLoading, isFalse);
    expect(state.hasError, isFalse);
  });

  test('shows no unfiltered results if there is no previous list', () async {
    final notifier = container.read(discoverProvider.notifier);
    when(() => service.readStoredDiscoveryUsers())
        .thenThrow(BlockedUsersReadException(StateError('offline')));

    await notifier.refresh();

    final state = container.read(discoverProvider);
    expect(state.results, isEmpty);
    expect(state.isLoading, isFalse);
    expect(state.hasError, isFalse);
  });

  test(
    'blocking removes the user and an in-flight read cannot restore it',
    () async {
      final notifier = container.read(discoverProvider.notifier);
      when(() => service.readStoredDiscoveryUsers())
          .thenAnswer((_) async => [blocked, visible]);
      await notifier.refresh();

      final pending = Completer<List<DiscoveryResult>>();
      when(() => service.readStoredDiscoveryUsers())
          .thenAnswer((_) => pending.future);
      final refresh = notifier.refresh();

      notifier.hideBlockedUser('blocked');
      expect(container.read(discoverProvider).results, [visible]);

      pending.complete([blocked, visible]);
      await refresh;
      expect(container.read(discoverProvider).results, [visible]);
    },
  );

  test(
    'blocking keeps visible results when an older load-more finishes',
    () async {
      when(() => service.hasMoreDiscoveryUsers).thenReturn(true);
      when(() => service.readStoredDiscoveryUsers())
          .thenAnswer((_) async => [blocked, visible]);
      final notifier = container.read(discoverProvider.notifier);
      await notifier.refresh();

      final pending = Completer<(List<DiscoveryResult>, bool)>();
      when(() => service.loadMoreDiscoveryUsers())
          .thenAnswer((_) => pending.future);
      final loadMore = notifier.loadMore();

      notifier.hideBlockedUser('blocked');
    pending.complete((const <DiscoveryResult>[], false));
      await loadMore;

      final state = container.read(discoverProvider);
      expect(state.results, [visible]);
      expect(state.hasMore, isFalse);
      expect(state.isLoadingMore, isFalse);
    },
  );
}
