// ignore_for_file: subtype_of_sealed_class, unnecessary_lambdas, avoid_redundant_argument_values
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/services/user_service.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockUsersRef;
  late MockCollectionReference mockPrivateUsersRef;
  late MockWriteBatch mockBatch;
  late UserService userService;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockUsersRef = MockCollectionReference();
    mockPrivateUsersRef = MockCollectionReference();
    mockBatch = MockWriteBatch();
    when(() => mockFirestore.collection('users')).thenReturn(mockUsersRef);
    when(
      () => mockFirestore.collection('user_private'),
    ).thenReturn(mockPrivateUsersRef);
    when(() => mockFirestore.batch()).thenReturn(mockBatch);
    when(() => mockBatch.commit()).thenAnswer((_) async {});
    userService = UserService(firestore: mockFirestore);
    registerFallbackValues();
  });

  group('UserService', () {
    group('createUserProfile', () {
      test('crea perfil correctamente en Firestore', () async {
        final mockDocRef = MockDocumentReference();
        final mockPrivateDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(
          () => mockPrivateUsersRef.doc('uid123'),
        ).thenReturn(mockPrivateDocRef);

        await userService.createUserProfile(
          uid: 'uid123',
          email: 'test@test.com',
          displayName: 'Test User',
          username: 'testuser',
        );

        final publicProfile =
            verify(
                  () => mockBatch.set<Map<String, dynamic>>(
                    mockDocRef,
                    captureAny(),
                    null,
                  ),
                ).captured.single
                as Map<String, dynamic>;
        final privateProfile =
            verify(
                  () => mockBatch.set<Map<String, dynamic>>(
                    mockPrivateDocRef,
                    captureAny(),
                    null,
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(publicProfile['displayName'], 'Test User');
        expect(publicProfile['username'], 'testuser');
        expect(publicProfile.containsKey('email'), isFalse);
        expect(privateProfile['email'], 'test@test.com');
        expect(privateProfile['friends'], isEmpty);
      });

      test('propaga error si Firestore falla', () async {
        final mockDocRef = MockDocumentReference();
        final mockPrivateDocRef = MockDocumentReference();
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockDocRef);
        when(
          () => mockPrivateUsersRef.doc('uid123'),
        ).thenReturn(mockPrivateDocRef);
        when(
          () => mockBatch.commit(),
        ).thenThrow(FirebaseException(plugin: 'firestore'));

        expect(
          () => userService.createUserProfile(
            uid: 'uid123',
            email: 'test@test.com',
            displayName: 'Test',
            username: 'testuser',
          ),
          throwsA(isA<FirebaseException>()),
        );
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
          'dailySongUpdatedAt': Timestamp.fromDate(DateTime(2026)),
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
        when(() => mockUsersRef.doc('uid123')).thenReturn(mockUserDocRef);
        when(
          () => mockPrivateUsersRef.doc('uid123'),
        ).thenReturn(mockPrivateDocRef);
        when(() => mockBatch.update(mockUserDocRef, any())).thenReturn(null);
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
    });
  });
}
