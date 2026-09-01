import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/pending_music_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persiste y restaura una edición musical completa', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = PendingMusicProfileStore(preferences);
    final edit = PendingMusicProfileEdit(
      revision: 'revision-1',
      artists: const [
        Artist(
          name: 'Radiohead',
          imageUrl: 'https://i.scdn.co/image/radiohead',
          genres: ['alternative rock'],
          spotifyId: '4Z8W4fKeB5YxbusRsdQVPb',
        ),
      ],
      createdAt: DateTime.utc(2026, 9),
    );

    await store.write('alice', edit);
    final restored = store.read('alice');

    expect(restored?.revision, 'revision-1');
    expect(restored?.createdAt, DateTime.utc(2026, 9));
    expect(restored?.blocked, isFalse);
    expect(restored?.artists.single.name, 'Radiohead');
    expect(restored?.artists.single.spotifyId, '4Z8W4fKeB5YxbusRsdQVPb');
  });

  test('una revisión antigua no elimina una edición más reciente', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = PendingMusicProfileStore(preferences);
    final edit = PendingMusicProfileEdit(
      revision: 'new',
      artists: const [Artist(name: 'New', imageUrl: '', genres: [])],
      createdAt: DateTime.utc(2026, 9),
    );
    await store.write('alice', edit);

    expect(await store.removeIfRevision('alice', 'old'), isFalse);
    expect(store.read('alice')?.revision, 'new');
    expect(await store.removeIfRevision('alice', 'new'), isTrue);
    expect(store.read('alice'), isNull);
  });

  test('ignora datos locales corruptos', () async {
    SharedPreferences.setMockInitialValues({
      'pending_music_profile_v1_alice': '{not-json',
    });
    final preferences = await SharedPreferences.getInstance();

    expect(PendingMusicProfileStore(preferences).read('alice'), isNull);
  });
}
