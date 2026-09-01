// ignore_for_file: subtype_of_sealed_class, unnecessary_lambdas, avoid_redundant_argument_values
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/user_service.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseFunctions mockFunctions;
  late MockHttpsCallable mockCallable;
  late MockCollectionReference mockUsersRef;
  late MockCollectionReference mockUsernamesRef;
  late MockCollectionReference mockPrivateUsersRef;
  late MockWriteBatch mockBatch;
  late UserService userService;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockFunctions = MockFirebaseFunctions();
    mockCallable = MockHttpsCallable();
    mockUsersRef = MockCollectionReference();
    mockUsernamesRef = MockCollectionReference();
    mockPrivateUsersRef = MockCollectionReference();
    mockBatch = MockWriteBatch();
    when(() => mockFirestore.collection('users')).thenReturn(mockUsersRef);
    when(
      () => mockFirestore.collection('usernames'),
    ).thenReturn(mockUsernamesRef);
    when(
      () => mockFirestore.collection('user_private'),
    ).thenReturn(mockPrivateUsersRef);
    when(() => mockFirestore.batch()).thenReturn(mockBatch);
    when(() => mockBatch.commit()).thenAnswer((_) async {});
    userService = UserService(
      firestore: mockFirestore,
      functions: mockFunctions,
    );
    registerFallbackValues();
  });

  group('UserService', () {
    group('createUserProfile', () {
      test('delega el alta atómica en la callable', () async {
        when(
          () => mockFunctions.httpsCallable('createUserProfile'),
        ).thenReturn(mockCallable);
        when(
          () => mockCallable.call<void>(any()),
        ).thenAnswer((_) async => MockHttpsCallableResult<void>());

        await userService.createUserProfile(
          displayName: ' Test User ',
          username: ' TestUser ',
        );

        final payload =
            verify(() => mockCallable.call<void>(captureAny())).captured.single
                as Map<String, dynamic>;
        expect(payload, {'displayName': 'Test User', 'username': 'testuser'});
      });

      test(
        'convierte already-exists en UsernameAlreadyTakenException',
        () async {
          final exception = MockFirebaseFunctionsException();
          when(() => exception.code).thenReturn('already-exists');
          when(
            () => mockFunctions.httpsCallable('createUserProfile'),
          ).thenReturn(mockCallable);
          when(() => mockCallable.call<void>(any())).thenThrow(exception);

          expect(
            () => userService.createUserProfile(
              displayName: 'Test',
              username: 'testuser',
            ),
            throwsA(isA<UsernameAlreadyTakenException>()),
          );
        },
      );
    });

    group('usernameExists', () {
      test('consulta el documento del username normalizado', () async {
        final reservationRef = MockDocumentReference();
        final reservation = MockDocumentSnapshot();
        when(() => mockUsernamesRef.doc('testuser')).thenReturn(reservationRef);
        when(() => reservationRef.get()).thenAnswer((_) async => reservation);
        when(() => reservation.exists).thenReturn(true);

        expect(await userService.usernameExists(' TestUser '), isTrue);
        verify(() => mockUsernamesRef.doc('testuser')).called(1);
      });

      test('considera deleted_user siempre reservado', () async {
        expect(
          await userService.usernameExists(AppUser.deletedUsername),
          isTrue,
        );
        verifyNever(() => mockUsernamesRef.doc(any()));
      });

      test('no consulta Firestore para un username inválido', () async {
        expect(await userService.usernameExists('ab'), isTrue);
        verifyNever(() => mockUsernamesRef.doc(any()));
      });
    });

    group('getUser', () {
      test('devuelve AppUser si el documento existe', () async {
        final mockDocRef = MockDocumentReference();
        final mockDocSnap = MockDocumentSnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get()).thenAnswer((_) async => mockDocSnap);
        when(() => mockDocSnap.exists).thenReturn(true);
        when(() => mockDocSnap.id).thenReturn('uid123');
        when(() => mockDocSnap.data()).thenReturn({
          'email': 'test@test.com',
          'displayName': 'Test User',
          'photoUrl': '',
          'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
          'lastLogin': Timestamp.fromDate(DateTime(2025, 1, 1)),
        });

        final user = await userService.getUser('uid123');

        expect(user, isNotNull);
        expect(user!.uid, 'uid123');
        expect(user.displayName, 'Test User');
      });

      test('devuelve null si el documento no existe', () async {
        final mockDocRef = MockDocumentReference();
        final mockDocSnap = MockDocumentSnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get()).thenAnswer((_) async => mockDocSnap);
        when(() => mockDocSnap.exists).thenReturn(false);

        final user = await userService.getUser('uid123');
        expect(user, isNull);
      });

      test('serverOnly ignora la caché y espera al servidor', () async {
        final mockDocRef = MockDocumentReference();
        final cachedSnapshot = MockDocumentSnapshot();
        final serverSnapshot = MockDocumentSnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get()).thenAnswer((_) async => cachedSnapshot);
        when(
          () => mockDocRef.get(const GetOptions(source: Source.server)),
        ).thenAnswer((_) async => serverSnapshot);
        for (final snapshot in [cachedSnapshot, serverSnapshot]) {
          when(() => snapshot.exists).thenReturn(true);
          when(() => snapshot.id).thenReturn('uid123');
        }
        when(
          () => cachedSnapshot.data(),
        ).thenReturn({'displayName': 'Cached name', 'username': 'cached'});
        when(
          () => serverSnapshot.data(),
        ).thenReturn({'displayName': 'Server name', 'username': 'server'});

        final cached = await userService.getUser('uid123');
        final fresh = await userService.getUser('uid123', serverOnly: true);

        expect(cached?.displayName, 'Cached name');
        expect(fresh?.displayName, 'Server name');
        verify(
          () => mockDocRef.get(const GetOptions(source: Source.server)),
        ).called(1);
      });

      test('cacheOnly consulta exclusivamente la caché persistente', () async {
        final mockDocRef = MockDocumentReference();
        final cachedSnapshot = MockDocumentSnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get(const GetOptions(source: Source.cache)))
            .thenAnswer((_) async => cachedSnapshot);
        when(() => cachedSnapshot.exists).thenReturn(true);
        when(() => cachedSnapshot.id).thenReturn('uid123');
        when(() => cachedSnapshot.data())
            .thenReturn({'displayName': 'Cached name', 'username': 'cached'});

        final cached = await userService.getUser('uid123', cacheOnly: true);

        expect(cached?.displayName, 'Cached name');
        verify(() => mockDocRef.get(const GetOptions(source: Source.cache)))
            .called(1);
        verifyNever(() => mockDocRef.get());
      });

      test('propaga error si Firestore falla', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(
          () => mockDocRef.get(),
        ).thenThrow(FirebaseException(plugin: 'firestore'));

        expect(
          () => userService.getUser('uid123'),
          throwsA(isA<FirebaseException>()),
        );
      });

      test('deduplica peticiones concurrentes del mismo usuario', () async {
        final mockDocRef = MockDocumentReference();
        final mockDocSnap = MockDocumentSnapshot();
        final completer = Completer<DocumentSnapshot<Map<String, dynamic>>>();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get()).thenAnswer((_) => completer.future);
        when(() => mockDocSnap.exists).thenReturn(true);
        when(() => mockDocSnap.id).thenReturn('uid123');
        when(
          () => mockDocSnap.data(),
        ).thenReturn({'displayName': 'Test User', 'photoUrl': ''});

        final first = userService.getUser('uid123');
        final second = userService.getUser('uid123');

        expect(identical(first, second), isTrue);
        verify(() => mockDocRef.get()).called(1);

        completer.complete(mockDocSnap);
        await Future.wait([first, second]);
      });

      test('cache aplica LRU y desaloja la entrada menos reciente', () async {
        final docRefs = <String, MockDocumentReference>{};

        for (var i = 0; i <= 200; i++) {
          final uid = 'uid_$i';
          final mockDocRef = MockDocumentReference();
          final mockDocSnap = MockDocumentSnapshot();
          docRefs[uid] = mockDocRef;

          when(() => mockUsersRef.doc(uid)).thenReturn(mockDocRef);
          when(() => mockDocRef.get()).thenAnswer((_) async => mockDocSnap);
          when(() => mockDocSnap.exists).thenReturn(true);
          when(() => mockDocSnap.id).thenReturn(uid);
          when(() => mockDocSnap.data()).thenReturn({
            'email': '$uid@test.com',
            'displayName': 'User $i',
            'photoUrl': '',
            'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
            'lastLogin': Timestamp.fromDate(DateTime(2025, 1, 1)),
          });
        }

        for (var i = 0; i < 200; i++) {
          await userService.getUser('uid_$i');
        }

        await userService.getUser('uid_0');
        await userService.getUser('uid_200');
        await userService.getUser('uid_1');
        await userService.getUser('uid_0');

        verify(() => docRefs['uid_1']!.get()).called(2);
        verify(() => docRefs['uid_0']!.get()).called(1);
      });
    });

    group('userExists', () {
      test('devuelve true si el usuario existe', () async {
        final mockDocRef = MockDocumentReference();
        final mockDocSnap = MockDocumentSnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get()).thenAnswer((_) async => mockDocSnap);
        when(() => mockDocSnap.exists).thenReturn(true);

        expect(await userService.userExists('uid123'), true);
      });

      test('devuelve false si no existe', () async {
        final mockDocRef = MockDocumentReference();
        final mockDocSnap = MockDocumentSnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.get()).thenAnswer((_) async => mockDocSnap);
        when(() => mockDocSnap.exists).thenReturn(false);

        expect(await userService.userExists('uid123'), false);
      });

      test('propaga error si Firestore falla', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(
          () => mockDocRef.get(),
        ).thenThrow(FirebaseException(plugin: 'firestore'));

        expect(
          () => userService.userExists('uid123'),
          throwsA(isA<FirebaseException>()),
        );
      });
    });

    group('updateLastLogin', () {
      test('actualiza el campo lastLogin', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockPrivateUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.update(any())).thenAnswer((_) async {});

        await userService.updateLastLogin('uid123');

        final captured = Map<String, dynamic>.from(
          verify(() => mockDocRef.update(captureAny())).captured.single as Map,
        );
        expect(captured.containsKey('lastLogin'), true);
        expect(captured['lastLogin'], isA<Timestamp>());
      });
    });

    group('updateProfile', () {
      test('actualiza displayName', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.update(any())).thenAnswer((_) async {});

        await userService.updateProfile('uid123', displayName: 'New Name');

        final captured =
            verify(() => mockDocRef.update(captureAny())).captured.single
                as Map<String, dynamic>;
        expect(captured['displayName'], 'New Name');
        expect(captured.containsKey('displayNameLower'), false);
        expect(captured['profileIdentityUpdatedAt'], isA<FieldValue>());
      });

      test('actualiza solo photoUrl si no se pasa displayName', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.update(any())).thenAnswer((_) async {});

        await userService.updateProfile(
          'uid123',
          photoUrl: 'https://new.photo',
        );

        final captured =
            verify(() => mockDocRef.update(captureAny())).captured.single
                as Map<String, dynamic>;
        expect(captured.containsKey('displayName'), false);
        expect(captured['photoUrl'], 'https://new.photo');
        expect(captured['profileIdentityUpdatedAt'], isA<FieldValue>());
      });

      test('no hace nada si no se pasan parámetros', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);

        await userService.updateProfile('uid123');

        verifyNever(() => mockDocRef.update(any()));
      });
    });

    group('searchUsers', () {
      test('devuelve lista vacía con query vacío', () async {
        final result = await userService.searchUsers('');
        expect(result, isEmpty);
      });

      test('devuelve lista vacía con query de solo espacios', () async {
        final result = await userService.searchUsers('   ');
        expect(result, isEmpty);
      });

      test('busca por username y excluye usuario actual', () async {
        final mockQuery1 = MockQuery();
        final mockQuery2 = MockQuery();
        final mockQuery3 = MockQuery();
        final mockQuerySnapshot = MockQuerySnapshot();

        final mockDoc = MockQueryDocumentSnapshot();
        when(() => mockDoc.id).thenReturn('other_uid');
        when(() => mockDoc.data()).thenReturn({
          'email': 'other@test.com',
          'displayName': 'Test User',
          'username': 'testuser',
          'photoUrl': '',
          'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
          'lastLogin': Timestamp.fromDate(DateTime(2025, 1, 1)),
        });

        when(
          () => mockUsersRef.where('username', isGreaterThanOrEqualTo: 'test'),
        ).thenReturn(mockQuery1);
        when(
          () => mockQuery1.where(
            'username',
            isLessThanOrEqualTo: any(named: 'isLessThanOrEqualTo'),
          ),
        ).thenReturn(mockQuery2);
        when(() => mockQuery2.limit(20)).thenReturn(mockQuery3);
        when(() => mockQuery3.get()).thenAnswer((_) async => mockQuerySnapshot);
        when(() => mockQuerySnapshot.docs).thenReturn([mockDoc]);

        final result = await userService.searchUsers(
          'test',
          excludeUid: 'my_uid',
        );

        expect(result, hasLength(1));
        expect(result.first.uid, 'other_uid');
      });
    });

    group('setDailySong', () {
      test('guarda la canción del día', () async {
        final mockDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.update(any())).thenAnswer((_) async {});

        const track = Track(
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          imageUrl: 'https://img.url',
          spotifyUrl: 'https://spotify.url',
        );

        await userService.setDailySong('uid123', track);

        final captured = Map<String, dynamic>.from(
          verify(() => mockDocRef.update(captureAny())).captured.single as Map,
        );
        final songData = Map<String, dynamic>.from(
          captured['dailySong'] as Map,
        );
        expect(songData['title'], 'Bohemian Rhapsody');
        expect(songData['artist'], 'Queen');
        expect(captured.containsKey('dailySongUpdatedAt'), true);
      });

      test('propaga el error si Firestore rechaza la publicación', () async {
        final mockDocRef = MockDocumentReference();
        final exception = FirebaseException(plugin: 'firestore');
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.update(any())).thenThrow(exception);

        const track = Track(
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          imageUrl: 'https://img.url',
        );

        expect(
          () => userService.setDailySong('uid123', track),
          throwsA(same(exception)),
        );
      });

      test('invalida la cachÃ© del usuario tras guardar la canciÃ³n', () async {
        final mockDocRef = MockDocumentReference();
        final oldSnapshot = MockDocumentSnapshot();
        final updatedSnapshot = MockDocumentSnapshot();
        var getCalls = 0;

        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(() => mockDocRef.update(any())).thenAnswer((_) async {});
        when(() => oldSnapshot.exists).thenReturn(true);
        when(() => oldSnapshot.id).thenReturn('uid123');
        when(() => oldSnapshot.data()).thenReturn({
          'displayName': 'Test User',
          'username': 'test',
          'photoUrl': '',
        });
        when(() => updatedSnapshot.exists).thenReturn(true);
        when(() => updatedSnapshot.id).thenReturn('uid123');
        when(() => updatedSnapshot.data()).thenReturn({
          'displayName': 'Test User',
          'username': 'test',
          'photoUrl': '',
          'dailySong': {
            'title': 'Bohemian Rhapsody',
            'artist': 'Queen',
            'imageUrl': 'https://img.url',
            'spotifyUrl': 'https://spotify.url',
          },
          'dailySongUpdatedAt': Timestamp.now(),
        });
        when(() => mockDocRef.get()).thenAnswer((_) async {
          getCalls++;
          return getCalls == 1 ? oldSnapshot : updatedSnapshot;
        });

        const track = Track(
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          imageUrl: 'https://img.url',
          spotifyUrl: 'https://spotify.url',
        );

        final before = await userService.getUser('uid123');
        await userService.setDailySong('uid123', track);
        final after = await userService.getUser('uid123');

        expect(before?.dailySong, isNull);
        expect(after?.dailySong?.title, 'Bohemian Rhapsody');
        expect(getCalls, 2);
      });
    });

    group('anonymizeUser', () {
      test('no borra rate_limits al anonimizar usuario', () async {
        final mockUserDocRef = MockDocumentReference();
        final mockPrivateDocRef = MockDocumentReference();
        final mockReservationRef = MockDocumentReference();
        final mockUserSnapshot = MockDocumentSnapshot();
        final mockReservationSnapshot = MockDocumentSnapshot();
        final mockPushTokensRef = MockCollectionReference();
        final mockPushTokensSnapshot = MockQuerySnapshot();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockUserDocRef);
        when(
          () => mockUserDocRef.get(),
        ).thenAnswer((_) async => mockUserSnapshot);
        when(
          () => mockUserSnapshot.data(),
        ).thenReturn({'username': 'testuser'});
        when(
          () => mockUsernamesRef.doc('testuser'),
        ).thenReturn(mockReservationRef);
        when(
          () => mockReservationRef.get(),
        ).thenAnswer((_) async => mockReservationSnapshot);
        when(
          () => mockReservationSnapshot.data(),
        ).thenReturn({'uid': 'uid123'});
        when(
          () => mockReservationSnapshot.reference,
        ).thenReturn(mockReservationRef);
        when(
          () => mockPrivateUsersRef.doc('uid123'),
        ).thenReturn(mockPrivateDocRef);
        when(
          () => mockPrivateDocRef.collection('push_tokens'),
        ).thenReturn(mockPushTokensRef);
        when(
          () => mockPushTokensRef.get(),
        ).thenAnswer((_) async => mockPushTokensSnapshot);
        when(() => mockPushTokensSnapshot.docs).thenReturn([]);
        when(() => mockBatch.update(mockUserDocRef, any())).thenReturn(null);
        when(() => mockBatch.delete(mockReservationRef)).thenReturn(null);
        when(() => mockBatch.delete(mockPrivateDocRef)).thenReturn(null);

        await userService.anonymizeUser('uid123');

        final publicUpdate = Map<String, dynamic>.from(
          verify(
                () => mockBatch.update<Map<String, dynamic>>(
                  mockUserDocRef,
                  captureAny(),
                ),
              ).captured.single
              as Map,
        );
        expect(publicUpdate['displayName'], AppUser.deletedDisplayName);
        expect(publicUpdate['username'], AppUser.deletedUsername);
        verify(() => mockBatch.delete(mockReservationRef)).called(1);
        verify(() => mockBatch.delete(mockPrivateDocRef)).called(1);
        verifyNever(() => mockFirestore.collection('rate_limits'));
      });
    });

    group('getUsersByIds', () {
      test('devuelve lista vacía con UIDs vacíos', () async {
        final result = await userService.getUsersByIds([]);
        expect(result, isEmpty);
      });

      test(
        'hace una sola consulta con exactamente 10 UIDs (límite whereIn)',
        () async {
          final uids = List.generate(10, (i) => 'uid_$i');

          final mockQuery = MockQuery();
          final mockSnapshot = MockQuerySnapshot();

          when(
            () => mockUsersRef.where(FieldPath.documentId, whereIn: uids),
          ).thenReturn(mockQuery);
          when(() => mockQuery.get()).thenAnswer((_) async => mockSnapshot);

          final mockDoc = MockQueryDocumentSnapshot();
          when(() => mockDoc.id).thenReturn('uid_0');
          when(() => mockDoc.data()).thenReturn({
            'email': 'u0@test.com',
            'displayName': 'User 0',
            'photoUrl': '',
            'createdAt': Timestamp.fromDate(DateTime(2025)),
            'lastLogin': Timestamp.fromDate(DateTime(2025)),
          });
          when(() => mockSnapshot.docs).thenReturn([mockDoc]);

          final result = await userService.getUsersByIds(uids);

          expect(result, hasLength(1));
          verify(() => mockQuery.get()).called(1);
        },
      );

      test('hace chunks de 10 para consultas whereIn', () async {
        // Generar 15 UIDs para forzar 2 chunks
        final uids = List.generate(15, (i) => 'uid_$i');

        final mockQuery1 = MockQuery();
        final mockQuery2 = MockQuery();
        final mockSnapshot1 = MockQuerySnapshot();
        final mockSnapshot2 = MockQuerySnapshot();

        // Primer chunk (10 items)
        when(
          () => mockUsersRef.where(
            FieldPath.documentId,
            whereIn: uids.sublist(0, 10),
          ),
        ).thenReturn(mockQuery1);
        when(() => mockQuery1.get()).thenAnswer((_) async => mockSnapshot1);

        // Segundo chunk (5 items)
        when(
          () => mockUsersRef.where(
            FieldPath.documentId,
            whereIn: uids.sublist(10, 15),
          ),
        ).thenReturn(mockQuery2);
        when(() => mockQuery2.get()).thenAnswer((_) async => mockSnapshot2);

        // Docs para cada snapshot
        final mockDoc1 = MockQueryDocumentSnapshot();
        when(() => mockDoc1.id).thenReturn('uid_0');
        when(() => mockDoc1.data()).thenReturn({
          'email': 'u0@test.com',
          'displayName': 'User 0',
          'photoUrl': '',
          'createdAt': Timestamp.fromDate(DateTime(2025)),
          'lastLogin': Timestamp.fromDate(DateTime(2025)),
        });

        final mockDoc2 = MockQueryDocumentSnapshot();
        when(() => mockDoc2.id).thenReturn('uid_10');
        when(() => mockDoc2.data()).thenReturn({
          'email': 'u10@test.com',
          'displayName': 'User 10',
          'photoUrl': '',
          'createdAt': Timestamp.fromDate(DateTime(2025)),
          'lastLogin': Timestamp.fromDate(DateTime(2025)),
        });

        when(() => mockSnapshot1.docs).thenReturn([mockDoc1]);
        when(() => mockSnapshot2.docs).thenReturn([mockDoc2]);

        final result = await userService.getUsersByIds(uids);

        expect(result, hasLength(2));
        verify(() => mockQuery1.get()).called(1);
        verify(() => mockQuery2.get()).called(1);
      });

      test('conserva el orden y reutiliza los perfiles cacheados', () async {
        final initialQuery = MockQuery();
        final initialSnapshot = MockQuerySnapshot();
        final user1Doc = MockQueryDocumentSnapshot();
        final user2Doc = MockQueryDocumentSnapshot();
        final initialUids = ['u2', 'u1'];

        when(
          () => mockUsersRef.where(FieldPath.documentId, whereIn: initialUids),
        ).thenReturn(initialQuery);
        when(() => initialQuery.get()).thenAnswer((_) async => initialSnapshot);
        when(() => initialSnapshot.docs).thenReturn([user1Doc, user2Doc]);
        when(() => user1Doc.id).thenReturn('u1');
        when(
          () => user1Doc.data(),
        ).thenReturn({'displayName': 'User 1', 'photoUrl': ''});
        when(() => user2Doc.id).thenReturn('u2');
        when(
          () => user2Doc.data(),
        ).thenReturn({'displayName': 'User 2', 'photoUrl': ''});

        final first = await userService.getUsersByIds(initialUids);
        final second = await userService.getUsersByIds(['u1', 'u2']);

        expect(first.map((user) => user.uid), ['u2', 'u1']);
        expect(second.map((user) => user.uid), ['u1', 'u2']);
        verify(() => initialQuery.get()).called(1);
      });
    });

    group('watchUsersByIds', () {
      test('emite cambios remotos sin reutilizar la caché temporal', () async {
        final query = MockQuery();
        final snapshots =
            StreamController<QuerySnapshot<Map<String, dynamic>>>();
        final firstSnapshot = MockQuerySnapshot();
        final secondSnapshot = MockQuerySnapshot();
        final firstDoc = MockQueryDocumentSnapshot();
        final secondDoc = MockQueryDocumentSnapshot();
        const friendIds = ['friend'];

        when(
          () => mockUsersRef.where(FieldPath.documentId, whereIn: friendIds),
        ).thenReturn(query);
        when(() => query.snapshots()).thenAnswer((_) => snapshots.stream);
        when(() => firstSnapshot.docs).thenReturn([firstDoc]);
        when(() => secondSnapshot.docs).thenReturn([secondDoc]);
        when(() => firstDoc.id).thenReturn('friend');
        when(() => secondDoc.id).thenReturn('friend');
        when(
          () => firstDoc.data(),
        ).thenReturn({'displayName': 'Friend', 'username': 'friend'});
        when(() => secondDoc.data()).thenReturn({
          'displayName': 'Friend',
          'username': 'friend',
          'dailySong': {
            'title': 'New song',
            'artist': 'Artist',
            'imageUrl': '',
            'spotifyUrl': '',
          },
          'dailySongUpdatedAt': Timestamp.now(),
        });

        final valuesFuture = userService
            .watchUsersByIds(friendIds)
            .take(2)
            .toList();
        await Future<void>.delayed(Duration.zero);
        snapshots
          ..add(firstSnapshot)
          ..add(secondSnapshot);

        final values = await valuesFuture;
        await snapshots.close();

        expect(values.first.single.dailySong, isNull);
        expect(values.last.single.dailySong?.title, 'New song');
      });
    });
  });
}
