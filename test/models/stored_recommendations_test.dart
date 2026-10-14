import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/models/stored_recommendations.dart';

void main() {
  final requestedAt = Timestamp.fromDate(DateTime(2026, 1, 1, 12));

  group('recommendationRefreshPending', () {
    test('sin petición de regeneración no hay nada pendiente', () {
      expect(recommendationRefreshPending(null), isFalse);
      expect(recommendationRefreshPending({'musicProfileVersion': 3}), isFalse);
    });

    test('la versión del perfil musical decide cuando existe', () {
      Map<String, dynamic> user(Object? generatedVersion) => {
        'recommendationsRefreshRequestedAt': requestedAt,
        'musicProfileVersion': 3,
        'recommendationsGeneratedForMusicProfileVersion': generatedVersion,
        // La versión prevalece sobre los timestamps.
        'recommendationsGeneratedAt': Timestamp.fromDate(DateTime(2027)),
      };

      expect(recommendationRefreshPending(user(null)), isTrue);
      expect(recommendationRefreshPending(user(2)), isTrue);
      expect(recommendationRefreshPending(user(3)), isFalse);
      expect(recommendationRefreshPending(user(4)), isFalse);
    });

    test('sin versión compara la generación con la petición', () {
      Map<String, dynamic> user(Timestamp? generatedAt) => {
        'recommendationsRefreshRequestedAt': requestedAt,
        'recommendationsGeneratedAt': generatedAt,
      };

      expect(recommendationRefreshPending(user(null)), isTrue);
      expect(
        recommendationRefreshPending(
          user(Timestamp.fromDate(DateTime(2026, 1, 1, 11))),
        ),
        isTrue,
      );
      expect(recommendationRefreshPending(user(requestedAt)), isFalse);
    });

    test('un serverTimestamp local sin resolver cuenta como pendiente', () {
      expect(
        recommendationRefreshPending({
          'recommendationsRefreshRequestedAt': null,
          'recommendationsGeneratedAt': requestedAt,
        }),
        isTrue,
      );
    });
  });

  group('shouldAwaitRecommendationRefresh', () {
    final pending = {'recommendationsRefreshRequestedAt': requestedAt};

    test('espera solo a una petición reciente', () {
      final requested = requestedAt.toDate();

      expect(
        shouldAwaitRecommendationRefresh(
          pending,
          now: requested.add(const Duration(seconds: 119)),
        ),
        isTrue,
      );
      expect(
        shouldAwaitRecommendationRefresh(
          pending,
          now: requested.add(const Duration(minutes: 2)),
        ),
        isFalse,
      );
    });

    test('no espera sin regeneración pendiente ni hora de petición', () {
      final now = requestedAt.toDate();

      expect(
        shouldAwaitRecommendationRefresh({
          ...pending,
          'recommendationsGeneratedAt': requestedAt,
        }, now: now),
        isFalse,
      );
      expect(
        shouldAwaitRecommendationRefresh({
          'recommendationsRefreshRequestedAt': null,
        }, now: now),
        isFalse,
      );
    });
  });

  group('discoveryResultFromStoredRecommendation', () {
    Map<String, dynamic> recommendation({
      Object? userId = 'other',
      Object? snapshotVersion = 1,
      Map<String, dynamic>? profile,
    }) => {
      'userId': ?userId,
      'snapshotVersion': snapshotVersion,
      'score': 72,
      'sharedArtistNames': ['A'],
      'sharedGenreNames': ['rock'],
      'profileSnapshot':
          profile ??
          {
            'displayName': 'Other',
            'username': 'other_user',
            'topArtistNames': ['A'],
            'topGenreNames': ['rock'],
          },
    };

    test('construye el resultado con el snapshot y la puntuación', () {
      final result = discoveryResultFromStoredRecommendation(
        docId: 'doc',
        data: recommendation(),
        currentUid: 'me',
      );

      expect(result, isNotNull);
      expect(result!.user.uid, 'other');
      expect(result.user.username, 'other_user');
      expect(result.score, 72);
      expect(result.sharedArtistNames, ['A']);
      expect(result.sharedGenreNames, ['rock']);
    });

    test('usa el id del documento si falta userId', () {
      final result = discoveryResultFromStoredRecommendation(
        docId: 'doc',
        data: recommendation(userId: null),
        currentUid: 'me',
      );

      expect(result?.user.uid, 'doc');
    });

    test('descarta recomendaciones que no se pueden mostrar', () {
      DiscoveryResult? check(Map<String, dynamic> data) =>
          discoveryResultFromStoredRecommendation(
            docId: 'doc',
            data: data,
            currentUid: 'me',
          );

      expect(check(recommendation(userId: 'me')), isNull);
      expect(check(recommendation(userId: '')), isNull);
      expect(check(recommendation(snapshotVersion: 2)), isNull);
      expect(check(recommendation()..remove('profileSnapshot')), isNull);
      expect(
        check(
          recommendation(
            profile: {
              'displayName': ' ',
              'username': 'other_user',
              'topArtistNames': ['A'],
            },
          ),
        ),
        isNull,
      );
      expect(
        check(
          recommendation(
            profile: {
              'displayName': 'Other',
              'username': 'other_user',
              'topArtistNames': <String>[],
              'topGenreNames': <String>[],
            },
          ),
        ),
        isNull,
      );
    });
  });
}
