import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/utils/music_compatibility.dart';

AppUser createUser({
  String uid = 'other',
  List<String> topArtistNames = const [],
  List<String> topArtistKeys = const [],
  List<String> topGenreNames = const [],
}) {
  return AppUser(
    uid: uid,
    displayName: 'Test',
    topArtistNames: topArtistNames,
    topArtistKeys: topArtistKeys,
    topGenreNames: topGenreNames,
  );
}

void main() {
  group('calculateCompatibility', () {
    test('sin coincidencias devuelve score 0', () {
      final result = calculateCompatibility(
        myArtistNames: ['Queen', 'Radiohead'],
        myGenreNames: ['rock', 'alternative'],
        otherUser: createUser(
          topArtistNames: ['Bad Bunny', 'Shakira'],
          topGenreNames: ['reggaeton', 'pop'],
        ),
      );

      expect(result.score, 0.0);
      expect(result.sharedArtistNames, isEmpty);
      expect(result.sharedGenreNames, isEmpty);
    });

    test('1 de 2 artistas en comun = 35 puntos', () {
      final result = calculateCompatibility(
        myArtistNames: ['Queen', 'Radiohead'],
        myGenreNames: [],
        otherUser: createUser(topArtistNames: ['Queen', 'Bad Bunny']),
      );

      expect(result.score, 35.0);
      expect(result.sharedArtistNames, ['Queen']);
    });

    test('1 de 2 generos en comun = 15 puntos', () {
      final result = calculateCompatibility(
        myArtistNames: [],
        myGenreNames: ['rock', 'jazz'],
        otherUser: createUser(topGenreNames: ['rock', 'reggaeton']),
      );

      expect(result.score, 15.0);
      expect(result.sharedGenreNames, ['rock']);
    });

    test('3 de 4 artistas + 2 de 3 generos = 73 puntos', () {
      final result = calculateCompatibility(
        myArtistNames: ['Queen', 'Radiohead', 'Muse', 'Coldplay'],
        myGenreNames: ['rock', 'alternative', 'pop'],
        otherUser: createUser(
          topArtistNames: ['Queen', 'Radiohead', 'Muse', 'Bad Bunny'],
          topGenreNames: ['rock', 'alternative', 'reggaeton'],
        ),
      );

      expect(result.score, 73.0);
      expect(result.sharedArtistNames.length, 3);
      expect(result.sharedGenreNames.length, 2);
    });

    test('5 artistas compartidos en perfiles grandes puntuan alto', () {
      final result = calculateCompatibility(
        myArtistNames: [
          'A1',
          'A2',
          'A3',
          'A4',
          'A5',
          'A6',
          'A7',
          'A8',
          'A9',
          'A10',
          'A11',
          'A12',
          'A13',
          'A14',
          'A15',
        ],
        myGenreNames: [],
        otherUser: createUser(
          topArtistNames: [
            'A1',
            'A2',
            'A3',
            'A4',
            'A5',
            'B6',
            'B7',
            'B8',
            'B9',
            'B10',
            'B11',
            'B12',
            'B13',
            'B14',
            'B15',
          ],
        ),
      );

      expect(result.score, 50.0);
      expect(result.sharedArtistNames, ['A1', 'A2', 'A3', 'A4', 'A5']);
    });

    test('ignora coincidencias posteriores al puesto 30', () {
      final result = calculateCompatibility(
        myArtistNames: [
          ...List.generate(30, (index) => 'Mine $index'),
          'Shared outside limit',
        ],
        myGenreNames: [],
        otherUser: createUser(
          topArtistNames: [
            ...List.generate(30, (index) => 'Other $index'),
            'Shared outside limit',
          ],
        ),
      );

      expect(result.score, 0.0);
      expect(result.sharedArtistNames, isEmpty);
    });

    test('5 artistas y 2 generos compartidos dan compatibilidad solida', () {
      final result = calculateCompatibility(
        myArtistNames: [
          'A1',
          'A2',
          'A3',
          'A4',
          'A5',
          'A6',
          'A7',
          'A8',
          'A9',
          'A10',
          'A11',
          'A12',
          'A13',
          'A14',
          'A15',
        ],
        myGenreNames: [
          'rock',
          'pop',
          'jazz',
          'metal',
          'folk',
          'indie',
          'soul',
          'punk',
        ],
        otherUser: createUser(
          topArtistNames: [
            'A1',
            'A2',
            'A3',
            'A4',
            'A5',
            'B6',
            'B7',
            'B8',
            'B9',
            'B10',
            'B11',
            'B12',
            'B13',
            'B14',
            'B15',
          ],
          topGenreNames: [
            'rock',
            'pop',
            'classical',
            'electronic',
            'hip hop',
            'latin',
            'blues',
            'ambient',
          ],
        ),
      );

      expect(result.score, 65.0);
    });

    test('todos los artistas en comun aportan 70 puntos', () {
      final result = calculateCompatibility(
        myArtistNames: ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
        myGenreNames: [],
        otherUser: createUser(
          topArtistNames: ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
        ),
      );

      expect(result.score, 70.0);
    });

    test('todos los generos en comun aportan 30 puntos', () {
      final result = calculateCompatibility(
        myArtistNames: [],
        myGenreNames: ['g1', 'g2', 'g3', 'g4', 'g5', 'g6', 'g7'],
        otherUser: createUser(
          topGenreNames: ['g1', 'g2', 'g3', 'g4', 'g5', 'g6', 'g7'],
        ),
      );

      expect(result.score, 30.0);
    });

    test('compatibilidad maxima (100 puntos) con 5 artistas y 5 generos', () {
      final result = calculateCompatibility(
        myArtistNames: ['A1', 'A2', 'A3', 'A4', 'A5'],
        myGenreNames: ['G1', 'G2', 'G3', 'G4', 'G5'],
        otherUser: createUser(
          topArtistNames: ['A1', 'A2', 'A3', 'A4', 'A5'],
          topGenreNames: ['G1', 'G2', 'G3', 'G4', 'G5'],
        ),
      );

      expect(result.score, 100.0);
    });

    test(
      '3 artistas y 1 genero identicos en perfiles pequenos = 100 puntos',
      () {
        final result = calculateCompatibility(
          myArtistNames: ['A1', 'A2', 'A3'],
          myGenreNames: ['rock'],
          otherUser: createUser(
            topArtistNames: ['A1', 'A2', 'A3'],
            topGenreNames: ['rock'],
          ),
        );

        expect(result.score, 100.0);
      },
    );

    test('el resultado incluye el usuario correcto', () {
      final otherUser = createUser(
        uid: 'other123',
        topArtistNames: ['Queen'],
        topGenreNames: ['rock'],
      );

      final result = calculateCompatibility(
        myArtistNames: ['Queen'],
        myGenreNames: ['rock'],
        otherUser: otherUser,
      );

      expect(result.user.uid, 'other123');
    });

    test('listas vacias para ambos usuarios devuelve score 0', () {
      final result = calculateCompatibility(
        myArtistNames: [],
        myGenreNames: [],
        otherUser: createUser(),
      );

      expect(result.score, 0.0);
    });

    test('normaliza mayusculas, espacios y duplicados al comparar', () {
      final result = calculateCompatibility(
        myArtistNames: [' Radiohead ', 'RADIOHEAD', 'Queen'],
        myGenreNames: [' Rock ', 'rock', 'jazz'],
        otherUser: createUser(
          topArtistNames: ['radiohead', 'queen', 'Muse'],
          topGenreNames: ['rock', 'pop'],
        ),
      );

      expect(result.score, 85.0);
      expect(result.sharedArtistNames, ['radiohead', 'queen']);
      expect(result.sharedGenreNames, ['rock']);
    });

    test('normaliza aliases de generos e ignora tags ruidosos al comparar', () {
      final result = calculateCompatibility(
        myArtistNames: [],
        myGenreNames: ['Hip-Hop', 'Canadian', 'seen live', 'R&B'],
        otherUser: createUser(
          topGenreNames: ['rap', 'rhythm and blues', '80s'],
        ),
      );

      expect(result.score, 30.0);
      expect(result.sharedGenreNames, ['hip hop', 'r&b']);
    });

    test('mismo spotifyId coincide aunque cambie el nombre visible', () {
      final result = calculateCompatibility(
        myArtistNames: ['Nombre anterior'],
        myArtistKeys: ['spotify:artist-123'],
        myGenreNames: [],
        otherUser: createUser(
          topArtistNames: ['Nombre nuevo'],
          topArtistKeys: ['spotify:artist-123'],
        ),
      );

      expect(result.score, 70.0);
      expect(result.sharedArtistNames, ['Nombre nuevo']);
    });

    test('spotifyIds distintos no coinciden aunque compartan nombre', () {
      final result = calculateCompatibility(
        myArtistNames: ['Phoenix'],
        myArtistKeys: ['spotify:artist-a'],
        myGenreNames: [],
        otherUser: createUser(
          topArtistNames: ['Phoenix'],
          topArtistKeys: ['spotify:artist-b'],
        ),
      );

      expect(result.score, 0.0);
      expect(result.sharedArtistNames, isEmpty);
    });

    test(
      'nombre normalizado conecta un artista sin ID con otro de Spotify',
      () {
        final result = calculateCompatibility(
          myArtistNames: ['Beyoncé'],
          myArtistKeys: ['spotify:beyonce-id'],
          myGenreNames: [],
          otherUser: createUser(topArtistNames: [' beyonce ']),
        );

        expect(result.score, 70.0);
        expect(result.sharedArtistNames, ['beyonce']);
      },
    );

    test('un fallback ambiguo solo puede coincidir con un artista', () {
      final result = calculateCompatibility(
        myArtistNames: ['Phoenix'],
        myGenreNames: [],
        otherUser: createUser(
          topArtistNames: ['Phoenix', 'Phoenix'],
          topArtistKeys: ['spotify:artist-a', 'spotify:artist-b'],
        ),
      );

      expect(result.score, 70.0);
      expect(result.sharedArtistNames, hasLength(1));
    });
  });

  group('compatibilityBetween', () {
    AppUser userWith({
      required String uid,
      required List<Artist> topArtists,
      required List<String> topArtistNames,
      List<String> topArtistKeys = const [],
    }) => AppUser(
      uid: uid,
      displayName: uid,
      topArtists: topArtists,
      topArtistNames: topArtistNames,
      topArtistKeys: topArtistKeys,
    );

    test('distingue homónimos por los spotifyId del perfil', () {
      final result = compatibilityBetween(
        userWith(
          uid: 'me',
          topArtists: const [
            Artist(name: 'Phoenix', imageUrl: '', genres: [], spotifyId: 'a'),
          ],
          topArtistNames: ['Phoenix'],
        ),
        userWith(
          uid: 'other',
          topArtists: const [
            Artist(name: 'Phoenix', imageUrl: '', genres: [], spotifyId: 'b'),
          ],
          topArtistNames: ['Phoenix'],
        ),
      );

      expect(result.score, 0.0);
      expect(result.sharedArtistNames, isEmpty);
    });

    test(
      'usa las claves guardadas si los artistas no cuadran con los nombres',
      () {
        final result = compatibilityBetween(
          userWith(
            uid: 'me',
            topArtists: const [
              Artist(name: 'Otro', imageUrl: '', genres: [], spotifyId: 'b'),
            ],
            topArtistNames: ['Phoenix'],
            topArtistKeys: ['spotify:a'],
          ),
          userWith(
            uid: 'other',
            topArtists: const [],
            topArtistNames: ['Phoenix'],
            topArtistKeys: ['spotify:a'],
          ),
        );

        expect(result.score, 70.0);
        expect(result.sharedArtistNames, ['Phoenix']);
      },
    );
  });
}
