import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/genre.dart';
import 'package:musi_link/models/track.dart';

void main() {
  group('AppUser', () {
    AppUser createTestUser({
      String uid = 'uid1',
      String displayName = 'Test User',
      String username = 'testuser',
      String photoUrl = '',
      List<Artist> topArtists = const [],
      List<Genre> topGenres = const [],
      List<String> topArtistNames = const [],
      List<String> topArtistKeys = const [],
      List<String> topGenreNames = const [],
      Track? dailySong,
      DateTime? dailySongUpdatedAt,
    }) {
      return AppUser(
        uid: uid,
        displayName: displayName,
        username: username,
        photoUrl: photoUrl,
        topArtists: topArtists,
        topGenres: topGenres,
        topArtistNames: topArtistNames,
        topArtistKeys: topArtistKeys,
        topGenreNames: topGenreNames,
        dailySong: dailySong,
        dailySongUpdatedAt: dailySongUpdatedAt,
      );
    }

    test('crea AppUser publico con campos requeridos y defaults', () {
      const user = AppUser(uid: 'uid1', displayName: 'Test User');

      expect(user.uid, 'uid1');
      expect(user.displayName, 'Test User');
      expect(user.username, '');
      expect(user.photoUrl, '');
      expect(user.topArtists, isEmpty);
      expect(user.topGenres, isEmpty);
      expect(user.topArtistNames, isEmpty);
      expect(user.topArtistKeys, isEmpty);
      expect(user.topGenreNames, isEmpty);
      expect(user.dailySong, isNull);
    });

    test('toFirestore serializa solo campos publicos base', () {
      final user = createTestUser(
        displayName: 'Pablo Garcia',
        username: 'pablo',
        photoUrl: 'https://photo.test/u.jpg',
      );

      final map = user.toFirestore();

      expect(map['displayName'], 'Pablo Garcia');
      expect(map['username'], 'pablo');
      expect(map['photoUrl'], 'https://photo.test/u.jpg');
      expect(map.containsKey('uid'), false);
      expect(map.containsKey('email'), false);
      expect(map.containsKey('friends'), false);
      expect(map.containsKey('lastLogin'), false);
    });

    test('copyWith actualiza displayName manteniendo otros campos', () {
      final original = createTestUser(displayName: 'Original');
      final updated = original.copyWith(displayName: 'Nuevo Nombre');

      expect(updated.displayName, 'Nuevo Nombre');
      expect(updated.uid, original.uid);
      expect(updated.username, original.username);
      expect(updated.topArtistNames, original.topArtistNames);
    });

    test('copyWith actualiza listas de artistas y generos', () {
      final original = createTestUser();
      final updated = original.copyWith(
        topArtistNames: ['Queen', 'Radiohead'],
        topArtistKeys: ['spotify:queen', 'spotify:radiohead'],
        topGenreNames: ['rock', 'alternative'],
      );

      expect(updated.topArtistNames, ['Queen', 'Radiohead']);
      expect(updated.topArtistKeys, ['spotify:queen', 'spotify:radiohead']);
      expect(updated.topGenreNames, ['rock', 'alternative']);
      expect(original.topArtistNames, isEmpty);
    });

    test('fromMap restaura claves de identidad de artistas', () {
      final user = AppUser.fromMap(
        uid: 'uid1',
        data: {
          'displayName': 'Test User',
          'topArtistNames': ['Beyoncé'],
          'topArtistKeys': ['spotify:6vWDO969PvNqNYHIOW5v0m'],
        },
      );

      expect(user, isNotNull);
      expect(user!.topArtistKeys, ['spotify:6vWDO969PvNqNYHIOW5v0m']);
    });

    test('fromMap descarta artistas posteriores al puesto 30', () {
      final user = AppUser.fromMap(
        uid: 'uid1',
        data: {
          'displayName': 'Test User',
          'topArtistNames': List.generate(50, (index) => 'Artist $index'),
          'topArtistKeys': List.generate(50, (index) => 'name:artist-$index'),
        },
      );

      expect(user, isNotNull);
      expect(user!.topArtistNames, hasLength(30));
      expect(user.topArtistKeys, hasLength(30));
      expect(user.topArtistNames.last, 'Artist 29');
    });

    test('fromMap descarta elementos musicales malformados sin lanzar', () {
      final user = AppUser.fromMap(
        uid: 'uid1',
        data: {
          'displayName': 'Test User',
          'topArtists': [
            1,
            {'name': 'Broken genres', 'genres': 1},
            {
              'name': 'Radiohead',
              'imageUrl': '',
              'genres': ['alternative rock'],
            },
          ],
          'topGenres': [
            1,
            {'name': 'broken', 'count': 'many'},
            {'name': 'alternative', 'count': 1, 'percentage': 50},
          ],
        },
      );

      expect(user, isNotNull);
      expect(user!.topArtists.map((artist) => artist.name), ['Radiohead']);
      expect(user.topGenres.map((genre) => genre.name), ['alternative']);
    });

    test('fromMap no convierte valores arbitrarios en nombres musicales', () {
      final user = AppUser.fromMap(
        uid: 'uid1',
        data: {
          'displayName': 'Test User',
          'topArtistNames': [
            1,
            {'injected': true},
            ' Radiohead ',
          ],
          'topArtistKeys': [false, ' name:radiohead '],
          'topGenreNames': [null, ' alternative '],
        },
      );

      expect(user!.topArtistNames, ['Radiohead']);
      expect(user.topArtistKeys, ['name:radiohead']);
      expect(user.topGenreNames, ['alternative']);
    });

    test('fromMap tolera tipos inválidos en timestamps y dailySong', () {
      final user = AppUser.fromMap(
        uid: 'uid1',
        data: {
          'displayName': 'Test User',
          'musicDataUpdatedAt': 'yesterday',
          'dailySong': 1,
          'dailySongUpdatedAt': false,
        },
      );

      expect(user, isNotNull);
      expect(user!.musicDataUpdatedAt, isNull);
      expect(user.dailySong, isNull);
      expect(user.dailySongUpdatedAt, isNull);
    });

    test('copyWith actualiza dailySong', () {
      final original = createTestUser();
      const track = Track(
        title: 'New Song',
        artist: 'New Artist',
        imageUrl: 'url',
      );
      final updated = original.copyWith(dailySong: track);

      expect(updated.dailySong, isNotNull);
      expect(updated.dailySong!.title, 'New Song');
      expect(original.dailySong, isNull);
    });

    test('mantiene la cancion activa durante las primeras 24 horas', () {
      final publishedAt = DateTime.utc(2026, 8, 10, 12);
      final user = createTestUser(
        dailySong: const Track(
          title: 'New Song',
          artist: 'New Artist',
          imageUrl: 'url',
        ),
        dailySongUpdatedAt: publishedAt,
      );

      expect(
        user.isDailySongActiveAt(
          publishedAt.add(const Duration(hours: 23, minutes: 59)),
        ),
        true,
      );
    });

    test('caduca la cancion al cumplirse exactamente 24 horas', () {
      final publishedAt = DateTime.utc(2026, 8, 10, 12);
      final user = createTestUser(
        dailySong: const Track(
          title: 'New Song',
          artist: 'New Artist',
          imageUrl: 'url',
        ),
        dailySongUpdatedAt: publishedAt,
      );

      expect(
        user.isDailySongActiveAt(publishedAt.add(AppUser.dailySongLifetime)),
        false,
      );
    });

    test('copyWith mantiene todos los campos si no se pasan parametros', () {
      final original = createTestUser(
        displayName: 'Keep This',
        topArtistNames: ['Keep Artist'],
      );

      final copy = original.copyWith();

      expect(copy.displayName, original.displayName);
      expect(copy.topArtistNames, original.topArtistNames);
      expect(copy.dailySong, original.dailySong);
    });

    test('isDeleted detecta marcador anonimo de cuenta eliminada', () {
      const deleted = AppUser(
        uid: 'deleted_uid',
        displayName: AppUser.deletedDisplayName,
        username: AppUser.deletedUsername,
      );
      final active = createTestUser();

      expect(deleted.isDeleted, true);
      expect(active.isDeleted, false);
    });
  });
}
