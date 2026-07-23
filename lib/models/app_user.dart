import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/models/genre.dart';
import 'package:musi_link/models/track.dart';

class AppUser {
  static const deletedDisplayName = 'Deleted user';
  static const deletedUsername = 'deleted_user';

  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
  final List<Artist> topArtists;
  final List<Genre> topGenres;
  final List<String> topArtistNames;
  final List<String> topGenreNames;
  final DateTime? musicDataUpdatedAt;
  final Track? dailySong;
  final DateTime? dailySongUpdatedAt;

  const AppUser({
    required this.uid,
    required this.displayName,
    this.username = '',
    this.photoUrl = '',
    this.topArtists = const [],
    this.topGenres = const [],
    this.topArtistNames = const [],
    this.topGenreNames = const [],
    this.musicDataUpdatedAt,
    this.dailySong,
    this.dailySongUpdatedAt,
  });

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
              .toList() ??
          [],
      topGenres:
          (data['topGenres'] as List<dynamic>?)
              ?.map((e) => Genre.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      topArtistNames:
          (data['topArtistNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      topGenreNames:
          (data['topGenreNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
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
      topGenreNames: topGenreNames ?? this.topGenreNames,
      musicDataUpdatedAt: musicDataUpdatedAt ?? this.musicDataUpdatedAt,
      dailySong: identical(dailySong, _unset)
          ? this.dailySong
          : dailySong as Track?,
      dailySongUpdatedAt: dailySongUpdatedAt ?? this.dailySongUpdatedAt,
    );
  }
}
