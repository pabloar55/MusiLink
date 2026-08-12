import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/genre.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

class AppUser {
  static const deletedDisplayName = 'Deleted user';
  static const deletedUsername = 'deleted_user';
  static const dailySongLifetime = Duration(hours: 24);

  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
  final List<Artist> topArtists;
  final List<Genre> topGenres;
  final List<String> topArtistNames;
  final List<String> topArtistKeys;
  final List<String> topGenreNames;
  final DateTime? musicDataUpdatedAt;
  final Track? _dailySong;
  final DateTime? dailySongUpdatedAt;

  const AppUser({
    required this.uid,
    required this.displayName,
    this.username = '',
    this.photoUrl = '',
    this.topArtists = const [],
    this.topGenres = const [],
    this.topArtistNames = const [],
    this.topArtistKeys = const [],
    this.topGenreNames = const [],
    this.musicDataUpdatedAt,
    this._dailySong,
    this.dailySongUpdatedAt,
  });

  /// Returns the song only while its 24-hour publication window is active.
  ///
  /// Profiles written by older clients without [dailySongUpdatedAt] remain
  /// visible until the backend can normalize them.
  Track? get dailySong =>
      isDailySongActiveAt(DateTime.now()) ? _dailySong : null;

  bool isDailySongActiveAt(DateTime now) {
    if (_dailySong == null) return false;
    final updatedAt = dailySongUpdatedAt;
    if (updatedAt == null) return true;
    return now.isBefore(updatedAt.add(dailySongLifetime));
  }

  static AppUser? fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return fromMap(uid: doc.id, data: data);
  }

  static AppUser? fromMap({
    required String uid,
    required Map<String, dynamic> data,
  }) {
    if (uid.isEmpty) return null;
    return AppUser(
      uid: uid,
      displayName: (data['displayName'] ?? '').toString(),
      username: (data['username'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      topArtists:
          (data['topArtists'] as List<dynamic>?)
              ?.map((e) => Artist.fromMap(e as Map<String, dynamic>))
              .take(MusicProfileLimits.maxArtists)
              .toList() ??
          [],
      topGenres:
          (data['topGenres'] as List<dynamic>?)
              ?.map((e) => Genre.fromMap(e as Map<String, dynamic>))
              .take(MusicProfileLimits.maxGenres)
              .toList() ??
          [],
      topArtistNames:
          (data['topArtistNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .take(MusicProfileLimits.maxArtists)
              .toList() ??
          [],
      topArtistKeys:
          (data['topArtistKeys'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .take(MusicProfileLimits.maxArtists)
              .toList() ??
          [],
      topGenreNames:
          (data['topGenreNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .take(MusicProfileLimits.maxGenres)
              .toList() ??
          [],
      musicDataUpdatedAt: (data['musicDataUpdatedAt'] as Timestamp?)?.toDate(),
      dailySong: data['dailySong'] != null
          ? Track.fromMap(data['dailySong'] as Map<String, dynamic>)
          : null,
      dailySongUpdatedAt: (data['dailySongUpdatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'username': username,
      'photoUrl': photoUrl,
    };
  }

  bool get isDeleted =>
      displayName == deletedDisplayName &&
      username == deletedUsername &&
      photoUrl.isEmpty;

  static const _unset = Object();

  AppUser copyWith({
    String? displayName,
    String? username,
    String? photoUrl,
    List<Artist>? topArtists,
    List<Genre>? topGenres,
    List<String>? topArtistNames,
    List<String>? topArtistKeys,
    List<String>? topGenreNames,
    DateTime? musicDataUpdatedAt,
    Object? dailySong = _unset,
    DateTime? dailySongUpdatedAt,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      topArtists: topArtists ?? this.topArtists,
      topGenres: topGenres ?? this.topGenres,
      topArtistNames: topArtistNames ?? this.topArtistNames,
      topArtistKeys: topArtistKeys ?? this.topArtistKeys,
      topGenreNames: topGenreNames ?? this.topGenreNames,
      musicDataUpdatedAt: musicDataUpdatedAt ?? this.musicDataUpdatedAt,
      dailySong: identical(dailySong, _unset)
          ? _dailySong
          : dailySong as Track?,
      dailySongUpdatedAt: dailySongUpdatedAt ?? this.dailySongUpdatedAt,
    );
  }
}
