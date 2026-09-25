import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/daily_song_reply_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/chat_service.dart';

import '../helpers/mocks.dart';

class MockChat extends Mock implements ChatService {}

void main() {
  const owner = AppUser(uid: 'alice', displayName: 'Alice');
  late MockChat chat;
  late MockFirebaseAuth auth;
  late ProviderContainer container;

  setUp(() async {
    chat = MockChat();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => user.uid).thenReturn('bob');
    when(() => auth.currentUser).thenReturn(user);
    container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        authStateProvider.overrideWith((ref) => Stream.value(user)),
        chatServiceProvider.overrideWithValue(chat),
      ],
    );
    container.listen(authStateProvider, (_, _) {});
    await container.read(authStateProvider.future);
    addTearDown(container.dispose);
  });

  test(
    'el envío sigue en segundo plano y conserva el error sin consumidores',
    () async {
      final pending = Completer<void>();
      when(() => chat.sendDailySongReply(owner, 'Draft'))
          .thenAnswer((_) => pending.future);
      final subscription = container.listen(dailySongReplyProvider, (_, _) {});
      final notifier = container.read(dailySongReplyProvider.notifier);
      final sent = notifier.send(owner, 'Draft');
      expect(container.read(dailySongReplyProvider), isEmpty);
      subscription.close();
      pending.completeError(StateError('offline'));
      final failed = await sent;
      expect(failed!.text, 'Draft');
      expect(container.read(dailySongReplyProvider), [failed]);
      when(() => chat.sendDailySongReply(owner, 'Edited'))
          .thenAnswer((_) async {});
      await notifier.send(owner, 'Edited', retryOf: failed);
      expect(container.read(dailySongReplyProvider), isEmpty);
    },
  );

  test('fallos concurrentes conservan cada borrador', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    when(() => chat.sendDailySongReply(owner, 'First'))
        .thenAnswer((_) => first.future);
    when(() => chat.sendDailySongReply(owner, 'Second'))
        .thenAnswer((_) => second.future);
    final notifier = container.read(dailySongReplyProvider.notifier);
    final sendingFirst = notifier.send(owner, 'First');
    final sendingSecond = notifier.send(owner, 'Second');
    second.completeError(StateError('offline'));
    await sendingSecond;
    first.completeError(StateError('offline'));
    await sendingFirst;
    expect(container.read(dailySongReplyProvider).map((reply) => reply.text), [
      'Second',
      'First',
    ]);
  });

  test('no restaura un borrador de otra sesión tras un error tardío', () async {
    final pending = Completer<void>();
    when(() => chat.sendDailySongReply(owner, 'Draft'))
        .thenAnswer((_) => pending.future);
    final sent = container
        .read(dailySongReplyProvider.notifier)
        .send(owner, 'Draft');
    final other = MockUser();
    when(() => other.uid).thenReturn('charlie');
    when(() => auth.currentUser).thenReturn(other);
    pending.completeError(StateError('offline'));
    expect(await sent, isNull);
    expect(container.read(dailySongReplyProvider), isEmpty);
  });
}
