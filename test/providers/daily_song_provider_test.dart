import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/service_providers.dart';

import '../helpers/mocks.dart';

void main() {
  const track = Track(
    title: 'Bohemian Rhapsody',
    artist: 'Queen',
    imageUrl: 'https://img.url',
  );

  test('expone éxito solo después de que el servicio confirme', () async {
    final service = MockUserService();
    final completer = Completer<void>();
    when(
      () => service.setDailySong('uid123', track),
    ).thenAnswer((_) => completer.future);
    final container = ProviderContainer(
      overrides: [userServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final pendingSave = container
        .read(dailySongSaveProvider.notifier)
        .save('uid123', track);

    expect(container.read(dailySongSaveProvider).isSaving, isTrue);
    completer.complete();
    final result = await pendingSave;

    expect(result, isTrue);
    expect(
      container.read(dailySongSaveProvider).status,
      DailySongSaveStatus.idle,
    );
  });

  test(
    'conserva la canción pendiente y permite reintentar tras un error',
    () async {
      final service = MockUserService();
      var attempts = 0;
      when(() => service.setDailySong('uid123', track)).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
      });
      final container = ProviderContainer(
        overrides: [userServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(dailySongSaveProvider.notifier);

      final firstResult = await notifier.save('uid123', track);

      expect(firstResult, isFalse);
      expect(container.read(dailySongSaveProvider).hasError, isTrue);
      expect(container.read(dailySongSaveProvider).pendingTrack, same(track));

      final retryResult = await notifier.retry('uid123');

      expect(retryResult, isTrue);
      expect(attempts, 2);
      expect(
        container.read(dailySongSaveProvider).status,
        DailySongSaveStatus.idle,
      );
    },
  );
}
