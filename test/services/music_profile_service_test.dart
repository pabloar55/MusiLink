// ignore_for_file: avoid_redundant_argument_values, subtype_of_sealed_class
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/artist.dart' as app;
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/services/artist_selector_controller.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:musi_link/services/music_catalog_service.dart';

import '../helpers/mocks.dart';

class MockMusicCatalogService extends Mock implements MusicCatalogService {}

MockQueryDocumentSnapshot buildRecommendationDoc(
  String uid, {
  double score = 42,
  List<String> sharedArtistNames = const ['Artist A'],
  List<String> sharedGenreNames = const ['rock'],
  List<String> topArtistNames = const ['Artist A', 'Artist B'],
  List<String> topGenreNames = const ['rock'],
  bool includeSnapshot = true,
}) {
  final doc = MockQueryDocumentSnapshot();
  when(() => doc.id).thenReturn(uid);
  when(() => doc.data()).thenReturn({
    'userId': uid,
    'score': score,
    'sharedArtistNames': sharedArtistNames,
    'sharedGenreNames': sharedGenreNames,
    if (includeSnapshot) ...{
      'snapshotVersion': 1,
      'profileSnapshot': {
        'displayName': 'User $uid',
        'username': 'user_$uid',
        'photoUrl': '',
        'topArtistNames': topArtistNames,
        'topGenreNames': topGenreNames,
      },
    },
  });
  return doc;
}

MockQuerySnapshot buildSnapshot(List<MockQueryDocumentSnapshot> docs) {
  final snap = MockQuerySnapshot();
  when(() => snap.docs).thenReturn(docs);
  return snap;
}

void main() {
  group('MusicProfileService discovery (backend recommendations)', () {
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFunctions mockFunctions;
    late MockHttpsCallable mockSaveMusicProfileCallable;
    late MockUser mockCurrentUser;
    late MockCollectionReference mockUsersRef;
    late MockCollectionReference mockPrivateUsersRef;
    late MockCollectionReference mockRecommendationsRef;
    late MockDocumentReference mockMyDocRef;
    late MockDocumentReference mockPrivateDocRef;
    late MockDocumentSnapshot mockMyDocSnap;
    late MockDocumentSnapshot mockPrivateDocSnap;
    late MockDocumentReference mockStoredRecommendationDocRef;
    late MockDocumentSnapshot mockStoredRecommendationDocSnap;
    late MockQuery mockRecommendationOrderQuery;
    late MockQuery mockRecommendationLimitQuery;
    late MockQuery mockRecommendationStartAfterQuery;
    late MockQuery mockRecommendationNextPageQuery;
    late MockMusicCatalogService mockMusicCatalogService;
    late MusicProfileService service;

    const myUid = 'me';

    void stubMyUserDoc({
      List<String> topArtistNames = const ['Artist A'],
      List<String> topGenreNames = const ['rock'],
      int? recommendationCount,
      Timestamp? recommendationsRefreshRequestedAt,
      Timestamp? recommendationsGeneratedAt,
    }) {
      when(() => mockUsersRef.doc(myUid)).thenReturn(mockMyDocRef);
      when(() => mockMyDocRef.get()).thenAnswer((_) async => mockMyDocSnap);
      when(() => mockMyDocRef.get(any()))
          .thenAnswer((_) async => mockMyDocSnap);
      when(() => mockMyDocSnap.exists).thenReturn(true);
      when(() => mockMyDocSnap.id).thenReturn(myUid);
      when(() => mockMyDocSnap.data()).thenReturn({
        'email': 'me@test.com',
        'displayName': 'Me',
        'photoUrl': '',
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'lastLogin': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'topArtistNames': topArtistNames,
        'topGenreNames': topGenreNames,
        'recommendationsCount': ?recommendationCount,
        'recommendationsRefreshRequestedAt': ?recommendationsRefreshRequestedAt,
        'recommendationsGeneratedAt': ?recommendationsGeneratedAt,
      });
    }

    void stubStoredRecommendations({
      required List<MockQueryDocumentSnapshot> recommendationDocs,
    }) {
      var nextPageIndex = 1;
      List<MockQueryDocumentSnapshot> pageAt(int index) =>
          recommendationDocs.skip(index * 20).take(20).toList(growable: false);

      when(() => mockRecommendationLimitQuery.get())
          .thenAnswer((_) async => buildSnapshot(pageAt(0)));
      when(() => mockRecommendationLimitQuery.get(any()))
          .thenAnswer((_) async => buildSnapshot(pageAt(0)));
      when(() => mockRecommendationNextPageQuery.get())
          .thenAnswer((_) async => buildSnapshot(pageAt(nextPageIndex++)));
      when(() => mockRecommendationNextPageQuery.get(any()))
          .thenAnswer((_) async => buildSnapshot(pageAt(nextPageIndex++)));
    }

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      mockFunctions = MockFirebaseFunctions();
      mockSaveMusicProfileCallable = MockHttpsCallable();
      mockCurrentUser = MockUser();
      mockUsersRef = MockCollectionReference();
      mockPrivateUsersRef = MockCollectionReference();
      mockRecommendationsRef = MockCollectionReference();
      mockMyDocRef = MockDocumentReference();
      mockPrivateDocRef = MockDocumentReference();
      mockMyDocSnap = MockDocumentSnapshot();
      mockPrivateDocSnap = MockDocumentSnapshot();
      mockStoredRecommendationDocRef = MockDocumentReference();
      mockStoredRecommendationDocSnap = MockDocumentSnapshot();
      mockRecommendationOrderQuery = MockQuery();
      mockRecommendationLimitQuery = MockQuery();
      mockRecommendationStartAfterQuery = MockQuery();
      mockRecommendationNextPageQuery = MockQuery();
      mockMusicCatalogService = MockMusicCatalogService();

      registerFallbackValues();
      registerFallbackValue(<Object?>[]);
      registerFallbackValue(<app.Artist>[]);
      registerFallbackValue(const GetOptions());

      when(() => mockAuth.currentUser).thenReturn(mockCurrentUser);
      when(() => mockCurrentUser.uid).thenReturn(myUid);
      when(() => mockFunctions.httpsCallable('saveMusicProfile'))
          .thenReturn(mockSaveMusicProfileCallable);
      when(() => mockSaveMusicProfileCallable.call<void>(any()))
          .thenAnswer((_) async => MockHttpsCallableResult<void>());
      when(() => mockFirestore.collection(any())).thenReturn(mockUsersRef);
      when(() => mockFirestore.collection('user_private'))
          .thenReturn(mockPrivateUsersRef);
      when(() => mockPrivateUsersRef.doc(myUid)).thenReturn(mockPrivateDocRef);
      when(() => mockPrivateDocRef.get())
          .thenAnswer((_) async => mockPrivateDocSnap);
      when(() => mockPrivateDocRef.get(any()))
          .thenAnswer((_) async => mockPrivateDocSnap);
      when(() => mockPrivateDocSnap.data()).thenReturn({'blockedUsers': []});

      stubMyUserDoc();
      when(() => mockMyDocRef.update(any())).thenAnswer((_) async {});

      when(() => mockMyDocRef.collection('recommendations'))
          .thenReturn(mockRecommendationsRef);
      when(() => mockRecommendationsRef.orderBy('score', descending: true))
          .thenReturn(mockRecommendationOrderQuery);
      when(() => mockRecommendationOrderQuery.limit(any()))
          .thenReturn(mockRecommendationLimitQuery);
      when(() => mockRecommendationOrderQuery.startAfterDocument(any()))
          .thenReturn(mockRecommendationStartAfterQuery);
      when(() => mockRecommendationStartAfterQuery.limit(any()))
          .thenReturn(mockRecommendationNextPageQuery);
      service = MusicProfileService(
        mockMusicCatalogService,
        firestore: mockFirestore,
        auth: mockAuth,
        functions: mockFunctions,
      );
    });

    test(
      'getStoredCompatibilityWith uses stored score and shared names',
      () async {
        const otherUser = AppUser(uid: 'other1', displayName: 'Other');
        when(() => mockRecommendationsRef.doc(otherUser.uid))
            .thenReturn(mockStoredRecommendationDocRef);
        when(() => mockStoredRecommendationDocRef.get())
            .thenAnswer((_) async => mockStoredRecommendationDocSnap);
        when(() => mockStoredRecommendationDocSnap.exists).thenReturn(true);
        when(() => mockStoredRecommendationDocSnap.data()).thenReturn({
          'score': 50,
          'sharedArtistNames': ['A', 'B'],
          'sharedGenreNames': ['rock'],
        });

        final result = await service.getStoredCompatibilityWith(otherUser);

        expect(result, isNotNull);
        expect(result!.user.uid, otherUser.uid);
        expect(result.score, 50);
        expect(result.sharedArtistNames, ['A', 'B']);
        expect(result.sharedGenreNames, ['rock']);
      },
    );

    group('saveManualArtists', () {
      test('completa fotos pendientes antes de guardar artistas', () async {
        when(() => mockMusicCatalogService.searchArtists('Radiohead', limit: 1))
            .thenAnswer(
              (_) async => const [
                app.Artist(
                  name: 'Radiohead',
                  imageUrl: 'https://i.scdn.co/image/radiohead123',
                  genres: ['alternative rock'],
                  spotifyId: '4Z8W4fKeB5YxbusRsdQVPb',
                ),
              ],
            );
        await service.saveManualArtists(const [
          app.Artist(name: 'Radiohead', imageUrl: '', genres: []),
          app.Artist(
            name: 'Queen',
            imageUrl: 'https://i.scdn.co/image/queen123',
            genres: ['rock'],
          ),
        ]);

        final payload = Map<String, dynamic>.from(
          verify(() => mockSaveMusicProfileCallable.call<void>(captureAny()))
                  .captured
                  .single
              as Map,
        );
        final artists = List<Map<String, dynamic>>.from(
          (payload['artists'] as List).map(
            (artist) => Map<String, dynamic>.from(artist as Map),
          ),
        );

        expect(artists[0]['name'], 'Radiohead');
        expect(artists[0]['imageUrl'], 'https://i.scdn.co/image/radiohead123');
        expect(artists[0]['genres'], ['alternative rock']);
        expect(artists[0]['spotifyId'], '4Z8W4fKeB5YxbusRsdQVPb');
        expect(artists[1]['imageUrl'], 'https://i.scdn.co/image/queen123');
        verifyNever(() => mockMyDocRef.update(any()));
      });

      test('guarda los homónimos elegidos en el selector', () async {
        const nirvanaUs = app.Artist(
          name: 'Nirvana',
          imageUrl: 'https://i.scdn.co/image/nirvana-us',
          genres: ['grunge'],
          spotifyId: '6olE6TJLqED3rqDCT0FyPh',
        );
        // El homónimo británico no tiene foto: el guardado intenta completarlo.
        const nirvanaUk = app.Artist(
          name: 'Nirvana',
          imageUrl: '',
          genres: ['psychedelic pop'],
          spotifyId: '0V4qHDaoXjv0zj3aT7k7Sx',
        );
        when(() => mockMusicCatalogService.searchArtists('Nirvana', limit: 1))
            .thenAnswer((_) async => const [nirvanaUs]);
        final selection = ArtistSelectorController(
          catalog: mockMusicCatalogService,
        );
        addTearDown(selection.dispose);
        when(() => mockMusicCatalogService.getRelatedArtists(any()))
            .thenAnswer((_) async => const []);

        selection
          ..toggle(nirvanaUs)
          ..toggle(nirvanaUk);
        await pumpEventQueue();
        await service.saveManualArtists(selection.selected);

        final payload = Map<String, dynamic>.from(
          verify(() => mockSaveMusicProfileCallable.call<void>(captureAny()))
                  .captured
                  .single
              as Map,
        );
        final artists = List<Map<String, dynamic>>.from(
          (payload['artists'] as List).map(
            (artist) => Map<String, dynamic>.from(artist as Map),
          ),
        );
        expect(artists.map((artist) => artist['spotifyId']), [
          nirvanaUs.spotifyId,
          nirvanaUk.spotifyId,
        ]);
        expect(artists[1]['imageUrl'], isEmpty);
        expect(artists[1]['genres'], ['psychedelic pop']);
      });

      test('guarda como máximo los primeros 30 artistas', () async {
        final selected = List.generate(
          50,
          (index) => app.Artist(
            name: 'Artist $index',
            imageUrl: 'https://i.scdn.co/image/artist$index',
            genres: const ['rock'],
            spotifyId: index.toString().padLeft(22, '0'),
          ),
        );
        await service.saveManualArtists(selected);

        final payload = Map<String, dynamic>.from(
          verify(() => mockSaveMusicProfileCallable.call<void>(captureAny()))
                  .captured
                  .single
              as Map,
        );
        final capturedArtists = payload['artists'] as List;
        expect(capturedArtists, hasLength(30));
        expect((capturedArtists.last as Map)['name'], 'Artist 29');
        verifyNever(() => mockMyDocRef.update(any()));
      });
    });

    group('stored discovery reads', () {
      test('filters blocked users from recommendations', () async {
        stubStoredRecommendations(
          recommendationDocs: [
            buildRecommendationDoc('blocked'),
            buildRecommendationDoc('visible'),
          ],
        );
        when(() => mockPrivateDocSnap.data()).thenReturn({
          'blockedUsers': ['blocked'],
        });

        final results = await service.readStoredDiscoveryUsers();

        expect(results.map((result) => result.user.uid), ['visible']);
      });

      test(
        'does not return recommendations when blocked users read fails',
        () async {
          stubStoredRecommendations(
            recommendationDocs: [buildRecommendationDoc('other1')],
          );
          when(() => mockPrivateDocRef.get()).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );

          await expectLater(
            service.readStoredDiscoveryUsers(),
            throwsA(isA<BlockedUsersReadException>()),
          );
          verifyNever(() => mockRecommendationLimitQuery.get());
        },
      );

      test(
        'a read started before cache invalidation cannot refill it',
        () async {
          final queryStarted = Completer<void>();
          final pendingQuery = Completer<QuerySnapshot<Map<String, dynamic>>>();
          when(() => mockRecommendationLimitQuery.get()).thenAnswer((_) {
            queryStarted.complete();
            return pendingQuery.future;
          });

          final read = service.readStoredDiscoveryUsers();
          await queryStarted.future;
          service.clearCache();
          pendingQuery.complete(
            buildSnapshot([buildRecommendationDoc('blocked')]),
          );
          await read;

          when(() => mockMyDocRef.get(any())).thenThrow(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
          expect(await service.readDiscoveryUsersFromLocalCache(), isNull);
          verify(() => mockMyDocRef.get(any())).called(2);
        },
      );

      test(
        'more than 20 stored recommendations sets hasMoreDiscoveryUsers true',
        () async {
          final recommendations = List.generate(
            25,
            (i) => buildRecommendationDoc('user$i', score: 100 - i.toDouble()),
          );
          stubStoredRecommendations(recommendationDocs: recommendations);

          final results = await service.readStoredDiscoveryUsers();

          expect(results.length, 20);
          expect(service.hasMoreDiscoveryUsers, isTrue);
          verify(() => mockRecommendationOrderQuery.limit(20)).called(1);
          verifyNever(
            () => mockUsersRef.where(any(), whereIn: any(named: 'whereIn')),
          );
        },
      );

      test(
        'less than 20 stored recommendations sets hasMoreDiscoveryUsers false',
        () async {
          final recommendations = List.generate(
            15,
            (i) => buildRecommendationDoc('user$i'),
          );
          stubStoredRecommendations(recommendationDocs: recommendations);

          final results = await service.readStoredDiscoveryUsers();

          expect(results.length, 15);
          expect(service.hasMoreDiscoveryUsers, isFalse);
        },
      );

      test('empty recommendation collection returns empty discovery', () async {
        stubStoredRecommendations(recommendationDocs: []);

        final results = await service.readStoredDiscoveryUsers();

        expect(results, isEmpty);
        expect(service.hasMoreDiscoveryUsers, isFalse);
      });

      test(
        'waits for a pending first recommendation generation before reading',
        () async {
          final requestedAt = Timestamp.now();
          stubMyUserDoc(
            recommendationCount: 0,
            recommendationsRefreshRequestedAt: requestedAt,
          );
          final generatedDoc = MockDocumentSnapshot();
          when(() => generatedDoc.exists).thenReturn(true);
          when(() => generatedDoc.id).thenReturn(myUid);
          when(() => generatedDoc.data()).thenReturn({
            'email': 'me@test.com',
            'displayName': 'Me',
            'photoUrl': '',
            'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
            'lastLogin': Timestamp.fromDate(DateTime(2025, 1, 1)),
            'topArtistNames': ['Artist A'],
            'topGenreNames': ['rock'],
            'recommendationsCount': 1,
            'recommendationsRefreshRequestedAt': requestedAt,
            'recommendationsGeneratedAt': Timestamp.fromMillisecondsSinceEpoch(
              requestedAt.millisecondsSinceEpoch + 1,
            ),
          });
          when(() => mockMyDocRef.snapshots())
              .thenAnswer((_) => Stream.value(generatedDoc));
          stubStoredRecommendations(
            recommendationDocs: [buildRecommendationDoc('other1')],
          );

          final results = await service.readStoredDiscoveryUsers();

          expect(results.map((result) => result.user.uid), ['other1']);
          verify(() => mockMyDocRef.snapshots()).called(1);
          verify(() => mockRecommendationLimitQuery.get()).called(1);
        },
      );

      test('excludes current user from stored recommendations', () async {
        final recommendations = [
          buildRecommendationDoc(myUid),
          buildRecommendationDoc('other1'),
          buildRecommendationDoc('other2'),
        ];
        stubStoredRecommendations(recommendationDocs: recommendations);

        final results = await service.readStoredDiscoveryUsers();

        expect(results.length, 2);
        expect(results.any((result) => result.user.uid == myUid), isFalse);
      });

      test('uses stored recommendation score and shared names', () async {
        final recommendations = [
          buildRecommendationDoc(
            'other1',
            score: 90,
            sharedArtistNames: ['A', 'B'],
            sharedGenreNames: ['rock'],
          ),
          buildRecommendationDoc(
            'other2',
            score: 20,
            sharedArtistNames: ['C'],
            sharedGenreNames: [],
          ),
        ];
        stubStoredRecommendations(recommendationDocs: recommendations);

        final results = await service.readStoredDiscoveryUsers();

        expect(results.first.user.uid, 'other1');
        expect(results.first.score, 90);
        expect(results.first.sharedArtistNames, ['A', 'B']);
        expect(results.first.sharedGenreNames, ['rock']);
        expect(results.last.user.uid, 'other2');
        expect(results.first.user.displayName, 'User other1');
        expect(results.first.user.topArtistNames, ['Artist A', 'Artist B']);
      });

      test('does not hydrate legacy recommendations from users', () async {
        final recommendations = [
          buildRecommendationDoc('legacy', includeSnapshot: false),
          buildRecommendationDoc('current'),
        ];
        stubStoredRecommendations(recommendationDocs: recommendations);

        final results = await service.readStoredDiscoveryUsers();

        expect(results.map((result) => result.user.uid), ['current']);
        verifyNever(
          () => mockUsersRef.where(any(), whereIn: any(named: 'whereIn')),
        );
      });

      test('local read after server read serves in-memory cache', () async {
        final recommendations = List.generate(
          5,
          (i) => buildRecommendationDoc('user$i'),
        );
        stubStoredRecommendations(recommendationDocs: recommendations);

        await service.readStoredDiscoveryUsers();
        await service.readDiscoveryUsersFromLocalCache();

        verify(() => mockRecommendationLimitQuery.get()).called(1);
      });

      test(
        'each explicit server read fetches stored recommendations again',
        () async {
          final recommendations = List.generate(
            5,
            (i) => buildRecommendationDoc('user$i'),
          );
          stubStoredRecommendations(recommendationDocs: recommendations);

          await service.readStoredDiscoveryUsers();
          await service.readStoredDiscoveryUsers();

          verify(() => mockRecommendationLimitQuery.get()).called(2);
        },
      );

      test('server read never requests a recommendation rebuild', () async {
        stubStoredRecommendations(recommendationDocs: []);

        await service.readStoredDiscoveryUsers();

        verifyNever(() => mockMyDocRef.update(any()));
      });

      test('generated empty result is a valid persistent cache hit', () async {
        stubMyUserDoc(recommendationCount: 0);
        stubStoredRecommendations(recommendationDocs: []);

        final results = await service.readDiscoveryUsersFromLocalCache();

        expect(results, isNotNull);
        expect(results, isEmpty);
      });

      test(
        'pending generation is never accepted as an empty cache hit',
        () async {
          stubMyUserDoc(
            recommendationCount: 0,
            recommendationsRefreshRequestedAt: Timestamp.now(),
          );
          stubStoredRecommendations(recommendationDocs: []);

          final results = await service.readDiscoveryUsersFromLocalCache();

          expect(results, isNull);
          verifyNever(() => mockRecommendationLimitQuery.get(any()));
        },
      );

      test('empty local query without generation metadata is a miss', () async {
        stubStoredRecommendations(recommendationDocs: []);

        final results = await service.readDiscoveryUsersFromLocalCache();

        expect(results, isNull);
      });
    });

    group('loadMoreDiscoveryUsers', () {
      test('without previous load returns empty list', () async {
        final (results, hasMore) = await service.loadMoreDiscoveryUsers();

        expect(results, isEmpty);
        expect(hasMore, isFalse);
      });

      test(
        'when total <= pageSize, loadMore does not expand results',
        () async {
          final recommendations = List.generate(
            5,
            (i) => buildRecommendationDoc('user$i'),
          );
          stubStoredRecommendations(recommendationDocs: recommendations);
          await service.readStoredDiscoveryUsers();

          final (results, hasMore) = await service.loadMoreDiscoveryUsers();

          expect(results.length, 5);
          expect(hasMore, isFalse);
        },
      );

      test('fetches the next page with a Firestore cursor', () async {
        final recommendations = List.generate(
          25,
          (i) => buildRecommendationDoc('user$i'),
        );
        stubStoredRecommendations(recommendationDocs: recommendations);

        await service.readStoredDiscoveryUsers();
        expect(service.hasMoreDiscoveryUsers, isTrue);

        final (allResults, hasMore) = await service.loadMoreDiscoveryUsers();

        expect(allResults.length, 25);
        expect(hasMore, isFalse);
        verify(() => mockRecommendationLimitQuery.get()).called(1);
        verify(
          () => mockRecommendationOrderQuery.startAfterDocument(
            recommendations[19],
          ),
        ).called(1);
        verify(() => mockRecommendationNextPageQuery.get()).called(1);
      });

      test('multiple loadMore calls page correctly from Firestore', () async {
        final recommendations = List.generate(
          50,
          (i) => buildRecommendationDoc('user$i'),
        );
        stubStoredRecommendations(recommendationDocs: recommendations);

        await service.readStoredDiscoveryUsers();
        expect(service.hasMoreDiscoveryUsers, isTrue);

        final (results1, hasMore1) = await service.loadMoreDiscoveryUsers();
        expect(results1.length, 40);
        expect(hasMore1, isTrue);

        final (results2, hasMore2) = await service.loadMoreDiscoveryUsers();
        expect(results2.length, 50);
        expect(hasMore2, isFalse);
        verify(() => mockRecommendationNextPageQuery.get()).called(2);
      });
    });
  });
}
