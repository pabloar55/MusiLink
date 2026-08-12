// ignore_for_file: subtype_of_sealed_class, unnecessary_lambdas, avoid_redundant_argument_values
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/chat_service.dart';

import '../helpers/mocks.dart';

/// Mock para CollectionReference de subcollection (messages)
class MockMessagesCollectionRef extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

void main() {
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseAuth mockAuth;
  late MockCollectionReference mockChatsRef;
  late MockCollectionReference mockPrivateUsersRef;
  late MockCollectionReference mockRateLimitsRef;
  late MockDocumentReference mockPrivateUserDocRef;
  late MockDocumentSnapshot mockPrivateUserSnap;
  late MockUser mockCurrentUser;
  late ChatService chatService;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
    mockChatsRef = MockCollectionReference();
    mockPrivateUsersRef = MockCollectionReference();
    mockRateLimitsRef = MockCollectionReference();
    mockPrivateUserDocRef = MockDocumentReference();
    mockPrivateUserSnap = MockDocumentSnapshot();
    mockCurrentUser = MockUser();

    when(() => mockFirestore.collection('chats')).thenReturn(mockChatsRef);
    when(
      () => mockFirestore.collection('user_private'),
    ).thenReturn(mockPrivateUsersRef);
    when(
      () => mockFirestore.collection('rate_limits'),
    ).thenReturn(mockRateLimitsRef);
    when(
      () => mockPrivateUsersRef.doc('current_uid'),
    ).thenReturn(mockPrivateUserDocRef);
    when(
      () => mockPrivateUserDocRef.get(),
    ).thenAnswer((_) async => mockPrivateUserSnap);
    when(() => mockPrivateUserSnap.data()).thenReturn({'blockedUsers': []});
    when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);
    when(() => mockCurrentUser.uid).thenReturn('current_uid');

    chatService = ChatService(firestore: mockFirestore, auth: mockAuth);
    registerFallbackValues();
  });

  group('ChatService', () {
    group('getOrCreateChat', () {
      test('devuelve chat existente si ya hay uno entre ambos', () async {
        // ID determinista: UIDs ordenados lexicográficamente
        const chatId = 'current_uid_other_uid';
        final mockDocRef = MockDocumentReference();
        final mockChatSnap = MockDocumentSnapshot();
        final fakeTransaction = FakeTransaction();

        mockFirestore.fakeTransaction = fakeTransaction;
        fakeTransaction.getResult = mockChatSnap;

        when(() => mockChatsRef.doc(chatId)).thenReturn(mockDocRef);
        when(() => mockChatSnap.exists).thenReturn(true);
        when(() => mockChatSnap.id).thenReturn(chatId);
        when(() => mockChatSnap.data()).thenReturn({
          'participants': ['current_uid', 'other_uid'],
          'lastMessage': 'hello',
          'lastMessageTime': Timestamp.fromDate(DateTime(2025, 1, 1)),
          'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        });

        final chat = await chatService.getOrCreateChat('other_uid');

        expect(chat.id, chatId);
        expect(chat.participants, contains('other_uid'));
        // No debería haberse llamado a set (el chat ya existía)
        expect(fakeTransaction.sets, isEmpty);
      });

      test('crea chat nuevo si no existe uno entre ambos', () async {
        const chatId = 'current_uid_other_uid';
        final mockDocRef = MockDocumentReference();
        final mockChatSnap = MockDocumentSnapshot();
        final fakeTransaction = FakeTransaction();

        mockFirestore.fakeTransaction = fakeTransaction;
        fakeTransaction.getResult = mockChatSnap;

        when(() => mockChatsRef.doc(chatId)).thenReturn(mockDocRef);
        when(() => mockDocRef.id).thenReturn(chatId);
        when(() => mockChatSnap.exists).thenReturn(false);

        final chat = await chatService.getOrCreateChat('other_uid');

        expect(chat.id, chatId);
        expect(chat.participants, containsAll(['current_uid', 'other_uid']));
        // tx.set debe haberse llamado con los participantes correctos
        expect(fakeTransaction.sets, hasLength(1));
        expect(fakeTransaction.sets.first.value['participants'], [
          'current_uid',
          'other_uid',
        ]);
      });

      test('rechaza abrir chat si el usuario esta bloqueado', () async {
        when(() => mockPrivateUserSnap.data()).thenReturn({
          'blockedUsers': ['other_uid'],
        });

        expect(
          () => chatService.getOrCreateChat('other_uid'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('getChats', () {
      test('oculta chats abiertos en los que aún no hay mensajes', () async {
        final participantsQuery = MockQuery();
        final orderedQuery = MockQuery();
        final snapshot = MockQuerySnapshot();
        final emptyChatDoc = MockQueryDocumentSnapshot();
        final chatWithMessageDoc = MockQueryDocumentSnapshot();
        final now = Timestamp.now();

        when(
          () =>
              mockChatsRef.where('participants', arrayContains: 'current_uid'),
        ).thenReturn(participantsQuery);
        when(
          () => participantsQuery.orderBy('lastMessageTime', descending: true),
        ).thenReturn(orderedQuery);
        when(
          () => orderedQuery.snapshots(),
        ).thenAnswer((_) => Stream.value(snapshot));
        when(
          () => snapshot.docs,
        ).thenReturn([emptyChatDoc, chatWithMessageDoc]);
        when(() => emptyChatDoc.id).thenReturn('current_uid_empty_uid');
        when(() => emptyChatDoc.data()).thenReturn({
          'participants': ['current_uid', 'empty_uid'],
          'lastMessage': '',
          'lastMessageTime': now,
          'createdAt': now,
          'unreadCounts': {'current_uid': 0, 'empty_uid': 0},
        });
        when(() => chatWithMessageDoc.id).thenReturn('current_uid_other_uid');
        when(() => chatWithMessageDoc.data()).thenReturn({
          'participants': ['current_uid', 'other_uid'],
          'lastMessage': 'Hola',
          'lastMessageTime': now,
          'createdAt': now,
          'unreadCounts': {'current_uid': 0, 'other_uid': 0},
        });

        final chats = await chatService.getChats().first;

        expect(chats, hasLength(1));
        expect(chats.single.id, 'current_uid_other_uid');
      });
    });

    group('sendMessage', () {
      test('crea mensaje y deja el resumen al backend', () async {
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCol = MockMessagesCollectionRef();
        final mockMsgDocRef = MockDocumentReference();
        final mockRateLimitDocRef = MockDocumentReference();
        final mockRateLimitSnap = MockDocumentSnapshot();
        final fakeTransaction = FakeTransaction();

        mockFirestore.fakeTransaction = fakeTransaction;
        fakeTransaction.getResult = mockRateLimitSnap;
        when(() => mockRateLimitSnap.data()).thenReturn({});
        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(
          () => mockRateLimitsRef.doc('current_uid'),
        ).thenReturn(mockRateLimitDocRef);
        when(
          () => mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCol);
        when(() => mockMessagesCol.doc()).thenReturn(mockMsgDocRef);

        await chatService.sendMessage(
          'chat_123',
          'Hello!',
          otherUid: 'other_uid',
        );

        // El cliente crea el mensaje; el trigger actualiza el resumen.
        final setCall = fakeTransaction.sets
            .firstWhere((entry) => entry.key == mockMsgDocRef)
            .value;
        expect(setCall['text'], 'Hello!');
        expect(setCall['senderId'], 'current_uid');
        expect(setCall['timestamp'], isA<FieldValue>());

        expect(fakeTransaction.updates, isEmpty);

        final limiterData = fakeTransaction.sets
            .firstWhere((entry) => entry.key == mockRateLimitDocRef)
            .value;
        expect(limiterData['lastMessageAt'], isA<FieldValue>());
        expect(limiterData['messageWindowStart'], isA<FieldValue>());
        expect(limiterData['messageCount'], 1);
      });

      test('rechaza enviar mensaje a un usuario bloqueado', () async {
        when(() => mockPrivateUserSnap.data()).thenReturn({
          'blockedUsers': ['other_uid'],
        });

        expect(
          () => chatService.sendMessage(
            'chat_123',
            'Hello!',
            otherUid: 'other_uid',
          ),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('sendTrackMessage', () {
      test('rechaza track si el texto supera el limite de bytes', () async {
        final longTitle = '🎵' * 501;
        final track = Track(
          title: longTitle,
          artist: 'Queen',
          imageUrl: 'https://img.url',
          spotifyUrl: 'https://spotify.url',
        );

        expect(
          () => chatService.sendTrackMessage(
            'chat_123',
            track,
            otherUid: 'other_uid',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('envía mensaje de tipo track con datos de la canción', () async {
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCol = MockMessagesCollectionRef();
        final mockMsgDocRef = MockDocumentReference();
        final mockRateLimitDocRef = MockDocumentReference();
        final mockRateLimitSnap = MockDocumentSnapshot();
        final fakeTransaction = FakeTransaction();

        mockFirestore.fakeTransaction = fakeTransaction;
        fakeTransaction.getResult = mockRateLimitSnap;
        when(() => mockRateLimitSnap.data()).thenReturn({});
        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(
          () => mockRateLimitsRef.doc('current_uid'),
        ).thenReturn(mockRateLimitDocRef);
        when(
          () => mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCol);
        when(() => mockMessagesCol.doc()).thenReturn(mockMsgDocRef);

        const track = Track(
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          imageUrl: 'https://img.url',
          spotifyUrl: 'https://spotify.url',
        );

        await chatService.sendTrackMessage(
          'chat_123',
          track,
          otherUid: 'other_uid',
        );

        // Verificar mensaje tipo track
        final setCall = fakeTransaction.sets
            .firstWhere((entry) => entry.key == mockMsgDocRef)
            .value;
        expect(setCall['type'], 'track');
        expect(setCall['text'], 'Bohemian Rhapsody - Queen');
        expect(setCall['trackData'], isNotNull);
        expect(setCall['timestamp'], isA<FieldValue>());

        expect(fakeTransaction.updates, isEmpty);
        final limiterData = fakeTransaction.sets
            .firstWhere((entry) => entry.key == mockRateLimitDocRef)
            .value;
        expect(limiterData['lastMessageAt'], isA<FieldValue>());
        expect(limiterData['messageWindowStart'], isA<FieldValue>());
        expect(limiterData['messageCount'], 1);
      });
    });

    group('softDeleteChat', () {
      test('solo marca deletedAt del usuario actual', () async {
        final mockChatDocRef = MockDocumentReference();

        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(() => mockChatDocRef.update(any())).thenAnswer((_) async {});

        await chatService.softDeleteChat('chat_123');

        final update = Map<String, dynamic>.from(
          verify(() => mockChatDocRef.update(captureAny())).captured.single
              as Map,
        );
        expect(update.keys.toList(), ['deletedAt.current_uid']);
        expect(update['deletedAt.current_uid'], isA<FieldValue>());
        verifyNever(() => mockChatDocRef.get());
        verifyNever(() => mockChatDocRef.delete());
      });
    });

    group('markMessagesAsRead', () {
      test('resetea el contador y marca mensajes como leídos', () async {
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCol = MockMessagesCollectionRef();
        final mockQuery1 = MockQuery();
        final mockQuery2 = MockQuery();
        final mockLimitQuery = MockQuery();
        final mockSnapshot = MockQuerySnapshot();
        final mockBatch = MockWriteBatch();

        final mockMsgDoc = MockQueryDocumentSnapshot();
        final mockMsgRef = MockDocumentReference();

        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(() => mockChatDocRef.update(any())).thenAnswer((_) async {});
        when(
          () => mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCol);
        when(
          () => mockMessagesCol.where('read', isEqualTo: false),
        ).thenReturn(mockQuery1);
        when(
          () => mockQuery1.where('senderId', isNotEqualTo: 'current_uid'),
        ).thenReturn(mockQuery2);
        when(() => mockQuery2.limit(499)).thenReturn(mockLimitQuery);
        when(() => mockLimitQuery.get()).thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.docs).thenReturn([mockMsgDoc]);
        when(() => mockMsgDoc.reference).thenReturn(mockMsgRef);

        when(() => mockFirestore.batch()).thenReturn(mockBatch);
        when(() => mockBatch.update(any(), any())).thenReturn(null);
        when(() => mockBatch.commit()).thenAnswer((_) async {});

        await chatService.markMessagesAsRead('chat_123');

        // Debe resetear el contador desnormalizado en el doc del chat
        final updateCall =
            verify(() => mockChatDocRef.update(captureAny())).captured.single
                as Map;
        expect(updateCall['unreadCounts.current_uid'], 0);

        // Y marcar los mensajes individuales como leídos
        verify(() => mockBatch.update(mockMsgRef, {'read': true})).called(1);
        verify(() => mockBatch.commit()).called(1);
      });

      test('resetea el contador aunque no haya mensajes sin leer', () async {
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCol = MockMessagesCollectionRef();
        final mockQuery1 = MockQuery();
        final mockQuery2 = MockQuery();
        final mockLimitQuery = MockQuery();
        final mockSnapshot = MockQuerySnapshot();

        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(() => mockChatDocRef.update(any())).thenAnswer((_) async {});
        when(
          () => mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCol);
        when(
          () => mockMessagesCol.where('read', isEqualTo: false),
        ).thenReturn(mockQuery1);
        when(
          () => mockQuery1.where('senderId', isNotEqualTo: 'current_uid'),
        ).thenReturn(mockQuery2);
        when(() => mockQuery2.limit(499)).thenReturn(mockLimitQuery);
        when(() => mockLimitQuery.get()).thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.docs).thenReturn([]);

        await chatService.markMessagesAsRead('chat_123');

        // El contador se resetea incluso sin mensajes que marcar
        verify(() => mockChatDocRef.update(any())).called(1);
        verifyNever(() => mockFirestore.batch());
      });

      test('ignora permission-denied al resetear contador', () async {
        final mockChatDocRef = MockDocumentReference();
        final mockMessagesCol = MockMessagesCollectionRef();
        final mockQuery1 = MockQuery();
        final mockQuery2 = MockQuery();
        final mockLimitQuery = MockQuery();
        final mockSnapshot = MockQuerySnapshot();

        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(() => mockChatDocRef.update(any())).thenThrow(
          FirebaseException(plugin: 'firestore', code: 'permission-denied'),
        );
        when(
          () => mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCol);
        when(
          () => mockMessagesCol.where('read', isEqualTo: false),
        ).thenReturn(mockQuery1);
        when(
          () => mockQuery1.where('senderId', isNotEqualTo: 'current_uid'),
        ).thenReturn(mockQuery2);
        when(() => mockQuery2.limit(499)).thenReturn(mockLimitQuery);
        when(() => mockLimitQuery.get()).thenAnswer((_) async => mockSnapshot);
        when(() => mockSnapshot.docs).thenReturn([]);

        await chatService.markMessagesAsRead('chat_123');

        verify(() => mockChatDocRef.update(any())).called(1);
      });
    });

    group('toggleReaction', () {
      late MockDocumentReference mockChatDocRef;
      late MockMessagesCollectionRef mockMessagesCol;
      late MockDocumentReference mockMsgRef;
      late MockDocumentSnapshot mockMsgSnap;
      late FakeTransaction fakeTransaction;

      setUp(() {
        mockChatDocRef = MockDocumentReference();
        mockMessagesCol = MockMessagesCollectionRef();
        mockMsgRef = MockDocumentReference();
        mockMsgSnap = MockDocumentSnapshot();
        fakeTransaction = FakeTransaction();

        when(() => mockChatsRef.doc('chat_123')).thenReturn(mockChatDocRef);
        when(
          () => mockChatDocRef.collection('messages'),
        ).thenReturn(mockMessagesCol);
        when(() => mockMessagesCol.doc('msg_123')).thenReturn(mockMsgRef);

        // FakeTransaction devuelve mockMsgSnap al hacer get()
        fakeTransaction.getResult = mockMsgSnap;

        // runTransaction ejecuta el callback con el fakeTransaction
        mockFirestore.fakeTransaction = fakeTransaction;
      });

      test('añade reacción si el usuario no ha reaccionado', () async {
        when(() => mockMsgSnap.exists).thenReturn(true);
        when(
          () => mockMsgSnap.data(),
        ).thenReturn({'reactions': <String, dynamic>{}});

        await chatService.toggleReaction('chat_123', 'msg_123', '👍');

        expect(fakeTransaction.updates, hasLength(1));
        final reactions = Map<String, dynamic>.from(
          fakeTransaction.updates.first.value['reactions'] as Map,
        );
        expect(reactions['👍'], contains('current_uid'));
      });

      test('quita reacción si el usuario ya reaccionó', () async {
        when(() => mockMsgSnap.exists).thenReturn(true);
        when(() => mockMsgSnap.data()).thenReturn({
          'reactions': {
            '👍': ['current_uid', 'other_uid'],
          },
        });

        await chatService.toggleReaction('chat_123', 'msg_123', '👍');

        expect(fakeTransaction.updates, hasLength(1));
        final reactions = Map<String, dynamic>.from(
          fakeTransaction.updates.first.value['reactions'] as Map,
        );
        final users = reactions['👍'] as List;
        expect(users, isNot(contains('current_uid')));
        expect(users, contains('other_uid'));
      });

      test('elimina emoji del mapa si ya no quedan usuarios', () async {
        when(() => mockMsgSnap.exists).thenReturn(true);
        when(() => mockMsgSnap.data()).thenReturn({
          'reactions': {
            '👍': ['current_uid'],
          },
        });

        await chatService.toggleReaction('chat_123', 'msg_123', '👍');

        expect(fakeTransaction.updates, hasLength(1));
        final reactions = Map<String, dynamic>.from(
          fakeTransaction.updates.first.value['reactions'] as Map,
        );
        expect(reactions.containsKey('👍'), false);
      });

      test('no hace nada si el mensaje no existe', () async {
        when(() => mockMsgSnap.exists).thenReturn(false);

        await chatService.toggleReaction('chat_123', 'msg_123', '👍');

        expect(fakeTransaction.updates, isEmpty);
      });
    });
  });
}
