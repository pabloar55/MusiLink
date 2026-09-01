import 'dart:convert';

import 'package:musi_link/models/artist.dart';
import 'package:musi_link/utils/music_profile_limits.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingMusicProfileEdit {
  const PendingMusicProfileEdit({
    required this.revision,
    required this.artists,
    required this.createdAt,
    this.blocked = false,
  });

  final String revision;
  final List<Artist> artists;
  final DateTime createdAt;
  final bool blocked;

  PendingMusicProfileEdit copyWith({bool? blocked}) => PendingMusicProfileEdit(
    revision: revision,
    artists: artists,
    createdAt: createdAt,
    blocked: blocked ?? this.blocked,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'blocked': blocked,
    'artists': artists.map((artist) => artist.toMap()).toList(),
  };

  static PendingMusicProfileEdit? fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['schemaVersion'] != 1) {
      return null;
    }
    final revision = value['revision'];
    final createdAt = value['createdAt'];
    final blocked = value['blocked'];
    final rawArtists = value['artists'];
    if (revision is! String ||
        revision.isEmpty ||
        createdAt is! String ||
        blocked is! bool ||
        rawArtists is! List ||
        rawArtists.length > MusicProfileLimits.maxArtists) {
      return null;
    }

    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) return null;
    final artists = <Artist>[];
    for (final rawArtist in rawArtists) {
      final artist = Artist.tryFromMap(rawArtist);
      if (artist == null) return null;
      artists.add(artist);
    }
    return PendingMusicProfileEdit(
      revision: revision,
      artists: List.unmodifiable(artists),
      createdAt: parsedCreatedAt.toUtc(),
      blocked: blocked,
    );
  }
}

class PendingMusicProfileStore {
  const PendingMusicProfileStore(this._preferences);

  final SharedPreferences _preferences;
  static const _keyPrefix = 'pending_music_profile_v1_';

  PendingMusicProfileEdit? read(String uid) {
    if (uid.isEmpty) return null;
    final raw = _preferences.getString('$_keyPrefix$uid');
    if (raw == null) return null;
    try {
      return PendingMusicProfileEdit.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String uid, PendingMusicProfileEdit edit) async {
    if (uid.isEmpty) return;
    final written = await _preferences.setString(
      '$_keyPrefix$uid',
      jsonEncode(edit.toJson()),
    );
    if (!written) throw StateError('Could not persist pending music profile.');
  }

  Future<bool> removeIfRevision(String uid, String revision) async {
    final current = read(uid);
    if (current == null || current.revision != revision) return false;
    final removed = await _preferences.remove('$_keyPrefix$uid');
    if (!removed) throw StateError('Could not clear pending music profile.');
    return true;
  }

  Future<bool> blockIfRevision(String uid, String revision) async {
    final current = read(uid);
    if (current == null || current.revision != revision) return false;
    await write(uid, current.copyWith(blocked: true));
    return true;
  }
}
