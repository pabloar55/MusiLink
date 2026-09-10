// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/chat_service.dart';

import '../helpers/mocks.dart';

void main() {
  late ChatService service;
  late MockFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late MockHttpsCallable callable;
  late MockDocumentReference chat;
  late MockCollectionReference messages;
  late MockQuery query;
  late MockWriteBatch batch;
  late StreamController<QuerySnapshot<Map<String, dynamic>>> snapshots;
  late Completer<MockHttpsCallableResult<void>> response;

  MockQuerySnapshot snapshot(List<Map<String, dynamic>> values) {
    final result = MockQuerySnapshot();
    final docs = values.map((value) {
      final doc = MockQueryDocumentSnapshot();
      when(() => doc.id).thenReturn(value['id'] as String? ?? 'message-1');
      when(() => doc.data()).thenReturn(value);
      when(() => doc.reference).thenReturn(MockDocumentReference());
      return doc;
    }).toList();
    when(() => result.docs).thenReturn(docs);
    return result;
  }

  setUp(() {
    registerFallbackValues();
    firestore = MockFirebaseFirestore();
    auth = MockFirebaseAuth();
    final user = MockUser();
    final functions = MockFirebaseFunctions();
    callable = MockHttpsCallable();
    final chats = MockCollectionReference();
    chat = MockDocumentReference();
    messages = MockCollectionReference();
    final newMessage = MockDocumentReference();
    query = MockQuery();
    batch = MockWriteBatch();
    snapshots = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    response = Completer<MockHttpsCallableResult<void>>();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('me');
    when(() => firestore.collection('chats')).thenReturn(chats);
    when(() => chats.doc('chat')).thenReturn(chat);
    when(() => chat.collection('messages')).thenReturn(messages);
    when(() => messages.doc()).thenReturn(newMessage);
    when(() => newMessage.id).thenReturn('message-1');
    when(() => messages.orderBy('timestamp', descending: true))
        .thenReturn(query);
    when(() => query.limit(30)).thenReturn(query);
    when(() => query.snapshots()).thenAnswer((_) => snapshots.stream);
    when(() => functions.httpsCallable('sendChatMessage')).thenReturn(callable);
    when(() => callable.call<void>(any())).thenAnswer((_) => response.future);
    when(() => firestore.batch()).thenReturn(batch);
    when(() => batch.commit()).thenAnswer((_) async {});
    service = ChatService(
      firestore: firestore,
      auth: auth,
      functions: functions,
    );
  });

  tearDown(() {
    unawaited(snapshots.close());
  });

  for (final track in [false, true]) {
    test(
      'optimistic ${track ? 'track' : 'text'} survives callable response and reconciles by ID',
      () async {
        final events = StreamIterator(service.getMessages('chat'));
        snapshots.add(snapshot([]));
        await events.moveNext();
        final sending = track
            ? service.sendTrackMessage(
                'chat',
                const Track(title: 'Song', artist: 'Artist', imageUrl: ''),
              )
            : service.sendMessage('chat', 'hello');
        await events.moveNext();
        expect(events.current.single.isPending, isTrue);
        expect(events.current.single.isTrack, track);
        expect(events.current.single.id, 'message-1');
        response.complete(MockHttpsCallableResult<void>());
        await sending;
        snapshots.add(snapshot([]));
        await events.moveNext();
        expect(events.current.single.isPending, isTrue);
        snapshots.add(
          snapshot([
            {
              'id': 'message-1',
              'senderId': 'me',
              'text': 'server',
              'delivered': true,
            },
          ]),
        );
        await events.moveNext();
        expect(events.current, hasLength(1));
        expect(events.current.single.isPending, isFalse);
        expect(events.current.single.delivered, isTrue);
        expect(events.current.single.text, 'server');
        expect(service.getCachedMessages('chat')!.single.isPending, isFalse);
        await events.cancel();
      },
    );
  }

  test(
    'failed send rolls back only the optimistic message and propagates error',
    () async {
      final events = StreamIterator(service.getMessages('chat'));
      snapshots.add(
        snapshot([
          {'id': 'old', 'senderId': 'me', 'text': 'existing'},
        ]),
      );
      await events.moveNext();
      final sending = service.sendMessage('chat', 'hello');
      await events.moveNext();
      expect(events.current, hasLength(2));
      final error = StateError('offline');
      final assertion = expectLater(sending, throwsA(same(error)));
      response.completeError(error, StackTrace.empty);
      await events.moveNext();
      expect(events.current.single.id, 'old');
      await assertion;
      await events.cancel();
    },
  );

  test('server confirmation wins over a late callable error', () async {
    final events = StreamIterator(service.getMessages('chat'));
    snapshots.add(snapshot([]));
    await events.moveNext();
    final sending = service.sendMessage('chat', 'hello');
    await events.moveNext();
    snapshots.add(
      snapshot([
        {'senderId': 'me', 'text': 'hello'},
      ]),
    );
    await events.moveNext();
    response.completeError(StateError('response lost'));
    await sending;
    expect(events.current.single.isPending, isFalse);
    await events.cancel();
  });

  test('acknowledges incoming legacy messages without marking read or own messages', () async {
    final events = StreamIterator(service.getMessages('chat'));
    final received = snapshot([
      {'id': 'own', 'senderId': 'me'},
      {'id': 'incoming', 'senderId': 'other'},
      {'id': 'delivered', 'senderId': 'other', 'delivered': true},
      {'id': 'read', 'senderId': 'other', 'read': true},
    ]);
    snapshots.add(received);
    await events.moveNext();
    final ref = received.docs[1].reference;
    verify(() => batch.update(ref, {'delivered': true})).called(1);
    verifyNever(() => chat.update(any()));
    verify(() => batch.commit()).called(1);
    await events.cancel();
  });

  test(
    'inbox receipt refreshes arrivals during an in-flight acknowledgement',
    () async {
      when(() => messages.where('read', isEqualTo: false)).thenReturn(query);
      when(() => query.where('senderId', isNotEqualTo: 'me')).thenReturn(query);
      when(() => query.limit(499)).thenReturn(query);
      final result = Completer<QuerySnapshot<Map<String, dynamic>>>();
      when(() => query.get()).thenAnswer((_) => result.future);
      final first = service.markMessagesAsDelivered('chat');
      final second = service.markMessagesAsDelivered('chat');
      final received = snapshot([
        {'senderId': 'other', 'read': false},
      ]);
      result.complete(received);
      await Future.wait([first, second]);
      verify(() => query.get()).called(2);
      final ref = received.docs.single.reference;
      verify(() => batch.update(ref, {'delivered': true})).called(2);
      verifyNever(() => chat.update(any()));
    },
  );
}
