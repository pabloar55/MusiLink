import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:musi_link/services/music_profile_sync_coordinator.dart';
import 'package:musi_link/services/pending_music_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMusicProfileService extends Mock implements MusicProfileService {}

const _firstArtists = [Artist(name: 'First', imageUrl: '', genres: [])];
const _lastArtists = [Artist(name: 'Last', imageUrl: '', genres: [])];

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

List<String>? _names(List<Artist>? artists) =>
    artists?.map((artist) => artist.name).toList();

void main() {
  setUpAll(() => registerFallbackValue(<Artist>[]));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('conserva localmente hasta que Firebase confirma', () async {
    final preferences = await SharedPreferences.getInstance();
    final profileService = _MockMusicProfileService();
    final save = Completer<void>();
    var savedCallbacks = 0;
    when(() => profileService.saveManualArtists(any()))
        .thenAnswer((_) => save.future);
    final coordinator = MusicProfileSyncCoordinator(
      store: PendingMusicProfileStore(preferences),
      profileService: profileService,
      currentUid: () => 'alice',
      onPending: (_, _) {},
      onSaved: (_) => savedCallbacks++,
    );
    addTearDown(coordinator.dispose);

    await coordinator.enqueue('alice', _firstArtists);

    expect(_names(coordinator.pendingArtists('alice')), ['First']);
    save.complete();
    await _flushAsync();
    await _flushAsync();
    expect(coordinator.pendingArtists('alice'), isNull);
    expect(savedCallbacks, 1);
  });

  test('reanuda una edición persistida después de reiniciar la app', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = PendingMusicProfileStore(preferences);
    await store.write(
      'alice',
      PendingMusicProfileEdit(
        revision: 'from-previous-session',
        artists: _firstArtists,
        createdAt: DateTime.utc(2026, 9),
      ),
    );
    final profileService = _MockMusicProfileService();
    when(() => profileService.saveManualArtists(any()))
        .thenAnswer((_) async {});
    final pending = <String>[];
    final coordinator = MusicProfileSyncCoordinator(
      store: store,
      profileService: profileService,
      currentUid: () => 'alice',
      onPending: (_, artists) => pending.add(artists.single.name),
      onSaved: (_) {},
    );
    addTearDown(coordinator.dispose);

    coordinator.resume();
    await _flushAsync();
    await _flushAsync();

    expect(pending, ['First']);
    expect(coordinator.pendingArtists('alice'), isNull);
    verify(() => profileService.saveManualArtists(any())).called(1);
  });

  test('la edición más reciente reemplaza una petición en vuelo', () async {
    final preferences = await SharedPreferences.getInstance();
    final profileService = _MockMusicProfileService();
    final firstSave = Completer<void>();
    final sent = <List<Artist>>[];
    when(() => profileService.saveManualArtists(any())).thenAnswer((call) {
      final artists = List<Artist>.from(
        call.positionalArguments.single as List<Artist>,
      );
      sent.add(artists);
      return sent.length == 1 ? firstSave.future : Future.value();
    });
    final coordinator = MusicProfileSyncCoordinator(
      store: PendingMusicProfileStore(preferences),
      profileService: profileService,
      currentUid: () => 'alice',
      onPending: (_, _) {},
      onSaved: (_) {},
    );
    addTearDown(coordinator.dispose);

    await coordinator.enqueue('alice', _firstArtists);
    await coordinator.enqueue('alice', _lastArtists);
    expect(_names(coordinator.pendingArtists('alice')), ['Last']);

    firstSave.complete();
    await _flushAsync();
    await _flushAsync();

    expect(sent.map(_names), [
      ['First'],
      ['Last'],
    ]);
    expect(coordinator.pendingArtists('alice'), isNull);
  });

  test('reanuda silenciosamente después de un error temporal', () async {
    final preferences = await SharedPreferences.getInstance();
    final profileService = _MockMusicProfileService();
    var calls = 0;
    when(() => profileService.saveManualArtists(any())).thenAnswer((_) async {
      calls++;
      if (calls == 1) {
        throw FirebaseException(plugin: 'functions', code: 'unavailable');
      }
    });
    final coordinator = MusicProfileSyncCoordinator(
      store: PendingMusicProfileStore(preferences),
      profileService: profileService,
      currentUid: () => 'alice',
      onPending: (_, _) {},
      onSaved: (_) {},
    );
    addTearDown(coordinator.dispose);

    await coordinator.enqueue('alice', _firstArtists);
    await _flushAsync();
    expect(_names(coordinator.pendingArtists('alice')), ['First']);

    coordinator.resume();
    await _flushAsync();
    await _flushAsync();
    expect(calls, 2);
    expect(coordinator.pendingArtists('alice'), isNull);
  });

  test('un error permanente se detiene hasta una edición nueva', () async {
    final preferences = await SharedPreferences.getInstance();
    final profileService = _MockMusicProfileService();
    var calls = 0;
    when(() => profileService.saveManualArtists(any())).thenAnswer((_) async {
      calls++;
      if (calls == 1) {
        throw FirebaseException(plugin: 'functions', code: 'invalid-argument');
      }
    });
    final coordinator = MusicProfileSyncCoordinator(
      store: PendingMusicProfileStore(preferences),
      profileService: profileService,
      currentUid: () => 'alice',
      onPending: (_, _) {},
      onSaved: (_) {},
    );
    addTearDown(coordinator.dispose);

    await coordinator.enqueue('alice', _firstArtists);
    await _flushAsync();
    coordinator.resume();
    await _flushAsync();
    expect(calls, 1);
    expect(_names(coordinator.pendingArtists('alice')), ['First']);

    await coordinator.enqueue('alice', _lastArtists);
    await _flushAsync();
    await _flushAsync();
    expect(calls, 2);
    expect(coordinator.pendingArtists('alice'), isNull);
  });
}
