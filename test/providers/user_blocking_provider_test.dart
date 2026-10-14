import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/models/relationship.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/session_scope_provider.dart';
import 'package:musi_link/providers/user_blocking_provider.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/services/music_profile_service.dart';

class _MockFriendService extends Mock implements FriendService {}

class _MockMusicProfileService extends Mock implements MusicProfileService {}

void main() {
  const other = DiscoveryResult(
    user: AppUser(uid: 'other', displayName: 'Other'),
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

  late _MockFriendService friendService;
  late _MockMusicProfileService musicProfileService;
  late ProviderContainer container;

  setUp(() async {
    friendService = _MockFriendService();
    musicProfileService = _MockMusicProfileService();
    when(() => friendService.blockUser(any())).thenAnswer((_) async {});
    when(() => friendService.unblockUser(any())).thenAnswer((_) async {});
    when(() => friendService.watchRelationship(any())).thenAnswer(
      (_) => Stream.value(const RelationshipResult(RelationshipStatus.none)),
    );
    when(() => musicProfileService.hasMoreDiscoveryUsers).thenReturn(false);
    when(() => musicProfileService.readStoredDiscoveryUsers())
        .thenAnswer((_) async => [other, visible]);

    container = ProviderContainer(
      overrides: [
        friendServiceProvider.overrideWithValue(friendService),
        musicProfileServiceProvider.overrideWithValue(musicProfileService),
      ],
    );
    addTearDown(container.dispose);
    container.listen(relationshipProvider('other'), (_, _) {});
    await container.read(discoverProvider.notifier).refresh();
    clearInteractions(friendService);
    clearInteractions(musicProfileService);
  });

  UserBlockingController controller() =>
      container.read(userBlockingControllerProvider);

  List<String> discoverUids() => [
    for (final result in container.read(discoverProvider).results)
      result.user.uid,
  ];

  test('bloquear oculta al usuario y descarta el estado derivado', () async {
    // La recarga posterior aún devuelve al bloqueado; no debe reaparecer.
    await controller().block('other');
    await pumpEventQueue();

    verify(() => friendService.blockUser('other')).called(1);
    verify(() => musicProfileService.clearCache()).called(1);
    verify(() => musicProfileService.readStoredDiscoveryUsers()).called(1);
    verify(() => friendService.watchRelationship('other')).called(1);
    expect(discoverUids(), ['visible']);
  });

  test('desbloquear vacía la caché y devuelve al usuario a Discover', () async {
    await controller().block('other');
    await pumpEventQueue();
    clearInteractions(musicProfileService);

    await controller().unblock('other');
    await pumpEventQueue();

    verify(() => friendService.unblockUser('other')).called(1);
    verify(() => musicProfileService.clearCache()).called(1);
    expect(discoverUids(), ['other', 'visible']);
  });

  test('si la escritura falla, propaga el error y no toca nada', () async {
    when(() => friendService.unblockUser(any()))
        .thenThrow(StateError('offline'));

    await expectLater(controller().unblock('other'), throwsStateError);

    verifyNever(() => musicProfileService.clearCache());
    verifyNever(() => musicProfileService.readStoredDiscoveryUsers());
    verifyNever(() => friendService.watchRelationship(any()));
  });

  test('si la sesión termina durante la escritura, no toca la nueva', () async {
    final write = Completer<void>();
    when(() => friendService.blockUser(any())).thenAnswer((_) => write.future);

    final blocking = controller().block('other');
    container.read(sessionScopeProvider.notifier).reset();
    write.complete();
    await blocking;
    await pumpEventQueue();

    verifyNever(() => musicProfileService.clearCache());
    verifyNever(() => musicProfileService.readStoredDiscoveryUsers());
  });
}
