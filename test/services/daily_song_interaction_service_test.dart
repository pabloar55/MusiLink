import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/daily_song_interaction_service.dart';

import '../helpers/mocks.dart';

void main() {
  final publishedAt = DateTime.now();
  final publication = (ownerId: 'alice', publishedAt: publishedAt);
  late MockFirebaseFirestore firestore;
  late MockDocumentReference like;
  late DailySongInteractionService service;

  setUp(() {
    registerFallbackValue(SetOptions(merge: true));
    firestore = MockFirebaseFirestore();
    final auth = MockFirebaseAuth();
    final user = MockUser();
    final users = MockCollectionReference();
    final owner = MockDocumentReference();
    final likes = MockCollectionReference();
    like = MockDocumentReference();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('bob');
    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc('alice')).thenReturn(owner);
    when(() => owner.collection('daily_song_likes')).thenReturn(likes);
    when(() => likes.doc('bob')).thenReturn(like);
    when(() => like.set(any(), any())).thenAnswer((_) async {});
    service = DailySongInteractionService(firestore: firestore, auth: auth);
  });

  test(
    'guarda un único like con la publicación exacta y hora del servidor',
    () async {
      await service.setLiked(publication, true);
      final data =
          verify(() => like.set(captureAny(), any())).captured.single as Map;
      expect(data['senderId'], 'bob');
      expect(data['publishedAt'], Timestamp.fromDate(publishedAt));
      expect(data['createdAt'], isA<FieldValue>());
    },
  );

  test('quitar un like antiguo no borra el de la nueva publicación', () async {
    final tx = FakeTransaction();
    firestore.fakeTransaction = tx;
    final snapshot = MockDocumentSnapshot();
    tx.getResult = snapshot;
    when(() => snapshot.data()).thenReturn({
      'publishedAt': Timestamp.fromDate(
        publishedAt.add(const Duration(seconds: 1)),
      ),
    });
    await service.setLiked(publication, false);
    expect(tx.deletes, isEmpty);
    when(() => snapshot.data())
        .thenReturn({'publishedAt': Timestamp.fromDate(publishedAt)});
    await service.setLiked(publication, false);
    expect(tx.deletes, [like]);
  });

  test('rechaza autolikes y canciones caducadas antes de escribir', () async {
    await expectLater(
      service.setLiked((ownerId: 'bob', publishedAt: publishedAt), true),
      throwsStateError,
    );
    await expectLater(
      service.setLiked((
        ownerId: 'alice',
        publishedAt: publishedAt.subtract(const Duration(hours: 25)),
      ), true),
      throwsStateError,
    );
    verifyNever(() => like.set(any(), any()));
  });
}
