import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart' as app;
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/utils/artist_identity.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:musi_link/utils/genre_normalizer.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

class MusicProfileService with AuthenticatedService {
  MusicProfileService(
    this._musicCatalogService, {
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final MusicCatalogService _musicCatalogService;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  FirebaseAuth get auth => _auth;

  late final CollectionReference<Map<String, dynamic>> _usersRef = _firestore
      .collection(FirestoreCollections.users);
  late final CollectionReference<Map<String, dynamic>> _privateUsersRef =
      _firestore.collection(FirestoreCollections.userPrivate);

  List<DiscoveryResult>? _cachedResults;
  DateTime? _cacheTime;
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastRecommendationDoc;
  Set<String>? _blockedUids;
  bool _hasMoreDiscoveryUsers = false;

  void clearCache() {
    _cachedResults = null;
    _cacheTime = null;
    _lastRecommendationDoc = null;
    _blockedUids = null;
    _hasMoreDiscoveryUsers = false;
  }

  static const _cacheTtl = Duration(minutes: 30);
  static const _recommendationGenerationWait = Duration(seconds: 15);
  static const _recentRecommendationRequestWindow = Duration(minutes: 2);
  static const _pageSize = 20;
  static const _recommendationSnapshotVersion = 1;
  static const _artistScoreWeight = 70.0;
  static const _genreScoreWeight = 30.0;
  static const _artistEvidenceTarget = 7.0;
  static const _genreEvidenceTarget = 4.0;

  bool get hasMoreDiscoveryUsers => _hasMoreDiscoveryUsers;

  bool get _isCacheValid =>
      _cachedResults != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheTtl;

  List<DiscoveryResult> _cacheFirstPage(
    List<DiscoveryResult> results, {
    required QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument,
    required bool hasMore,
  }) {
    _cachedResults = results;
    _cacheTime = DateTime.now();
    _lastRecommendationDoc = lastDocument;
    _hasMoreDiscoveryUsers = hasMore;
    return List<DiscoveryResult>.unmodifiable(results);
  }

  Future<void> saveManualArtists(
    String uid,
    List<app.Artist> selectedArtists,
  ) async {
    try {
      final artists = await _hydrateMissingArtistDetails(
        selectedArtists.take(MusicProfileLimits.maxArtists).toList(),
      );
      final genres = _musicCatalogService.getTopGenresFromArtists(
        artists,
        MusicProfileLimits.maxGenres,
      );
      final updatedAt = FieldValue.serverTimestamp();

      await _usersRef.doc(uid).update({
        'topArtists': artists.map((a) => a.toMap()).toList(),
        'topGenres': genres.map((g) => g.toMap()).toList(),
        'topArtistNames': artists.map((a) => a.name).toList(),
        'topArtistKeys': artistIdentityKeys(artists),
        'topGenreNames': genres.map((g) => g.name).toList(),
        'artistIdentityVersion': artistIdentityVersion,
        'musicDataUpdatedAt': updatedAt,
        // Permite distinguir un resultado vacío real del breve intervalo
        // entre guardar el perfil y terminar la Cloud Function.
        'recommendationsRefreshRequestedAt': updatedAt,
      });
      clearCache();
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  Future<List<app.Artist>> _hydrateMissingArtistDetails(
    List<app.Artist> artists,
  ) {
    return Future.wait(artists.map(_hydrateMissingArtistDetailsFor));
  }

  Future<app.Artist> _hydrateMissingArtistDetailsFor(app.Artist artist) async {
    if (artist.imageUrl.trim().isNotEmpty) return artist;

    try {
      final results = await _musicCatalogService.searchArtists(
        artist.name,
        limit: 1,
      );
      if (results.isEmpty) return artist;

      final enriched = results.first;
      if (_normalizedMusicKey(enriched.name) !=
          _normalizedMusicKey(artist.name)) {
        return artist;
      }

      return app.Artist(
        name: artist.name,
        imageUrl: enriched.imageUrl.isNotEmpty
            ? enriched.imageUrl
            : artist.imageUrl,
        genres: enriched.genres.isNotEmpty ? enriched.genres : artist.genres,
        spotifyId: enriched.spotifyId ?? artist.spotifyId,
      );
    } catch (_) {
      return artist;
    }
  }

  /// Reads only local memory and Firestore's persistent cache.
  ///
  /// Returns null when there is not enough cached data to know the current
  /// result, and an empty list when the backend has generated a valid empty
  /// recommendation set.
  Future<List<DiscoveryResult>?> readDiscoveryUsersFromLocalCache() async {
    if (_isCacheValid) {
      return List<DiscoveryResult>.unmodifiable(_cachedResults!);
    }

    try {
      const opts = GetOptions(source: Source.cache);

      final myDoc = await _usersRef.doc(currentUid).get(opts);
      if (!myDoc.exists) return null;

      final myUser = AppUser.fromFirestore(myDoc);
      if (myUser == null) return null;
      if (myUser.topArtistNames.isEmpty && myUser.topGenreNames.isEmpty) {
        return null;
      }
      if (_recommendationRefreshIsPending(myDoc.data())) return null;

      _blockedUids = null;
      final stored = await _fetchStoredRecommendationsPage(options: opts);
      final recommendationCount = myDoc.data()?['recommendationsCount'] as int?;
      if (stored.storedCount == 0 && recommendationCount != 0) return null;

      return _cacheFirstPage(
        stored.results,
        lastDocument: stored.lastDocument,
        hasMore: stored.hasMore,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') return null;
      await reportError(e, StackTrace.current);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the recommendation set currently stored on the server.
  ///
  /// This operation never requests a recommendation rebuild.
  Future<List<DiscoveryResult>> readStoredDiscoveryUsers() async {
    try {
      _lastRecommendationDoc = null;
      _blockedUids = null;
      _hasMoreDiscoveryUsers = false;
      var myDoc = await _usersRef.doc(currentUid).get();
      if (!myDoc.exists) {
        return _cacheFirstPage(const [], lastDocument: null, hasMore: false);
      }
      if (_shouldWaitForRecommendationRefresh(myDoc.data())) {
        myDoc = await _waitForRecommendationRefresh(myDoc);
      }

      final myUser = AppUser.fromFirestore(myDoc);
      if (myUser == null) {
        return _cacheFirstPage(const [], lastDocument: null, hasMore: false);
      }
      if (myUser.topArtistNames.isEmpty && myUser.topGenreNames.isEmpty) {
        return _cacheFirstPage(const [], lastDocument: null, hasMore: false);
      }

      final stored = await _fetchStoredRecommendationsPage();
      return _cacheFirstPage(
        stored.results,
        lastDocument: stored.lastDocument,
        hasMore: stored.hasMore,
      );
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  bool _recommendationRefreshIsPending(Map<String, dynamic>? data) {
    if (data == null ||
        !data.containsKey('recommendationsRefreshRequestedAt')) {
      return false;
    }

    final requestedAt = data['recommendationsRefreshRequestedAt'];
    final generatedAt = data['recommendationsGeneratedAt'];
    if (requestedAt is! Timestamp) {
      // A local serverTimestamp can temporarily resolve as null.
      return true;
    }
    return generatedAt is! Timestamp ||
        generatedAt.millisecondsSinceEpoch < requestedAt.millisecondsSinceEpoch;
  }

  bool _shouldWaitForRecommendationRefresh(Map<String, dynamic>? data) {
    if (!_recommendationRefreshIsPending(data)) return false;

    final requestedAt = data?['recommendationsRefreshRequestedAt'];
    if (requestedAt is! Timestamp) return false;
    final age = DateTime.now().difference(requestedAt.toDate());
    return age < _recentRecommendationRequestWindow;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _waitForRecommendationRefresh(
    DocumentSnapshot<Map<String, dynamic>> current,
  ) async {
    try {
      return await _usersRef
          .doc(currentUid)
          .snapshots()
          .firstWhere(
            (snapshot) =>
                snapshot.exists &&
                !_recommendationRefreshIsPending(snapshot.data()),
          )
          .timeout(_recommendationGenerationWait);
    } on TimeoutException {
      // No convertimos un fallo de generación en un bloqueo permanente:
      // tras el margen de espera se muestra el último estado disponible.
      return current;
    } on FirebaseException {
      return current;
    }
  }

  Future<(List<DiscoveryResult>, bool hasMore)> loadMoreDiscoveryUsers() async {
    if (_cachedResults == null || !_hasMoreDiscoveryUsers) {
      return (
        List<DiscoveryResult>.unmodifiable(_cachedResults ?? const []),
        false,
      );
    }

    final stored = await _fetchStoredRecommendationsPage(
      startAfter: _lastRecommendationDoc,
    );
    final knownUids = _cachedResults!.map((result) => result.user.uid).toSet();
    final nextResults = stored.results
        .where((result) => knownUids.add(result.user.uid))
        .toList();
    _cachedResults = [..._cachedResults!, ...nextResults];
    _lastRecommendationDoc = stored.lastDocument;
    _hasMoreDiscoveryUsers = stored.hasMore;
    _cacheTime = DateTime.now();

    return (
      List<DiscoveryResult>.unmodifiable(_cachedResults!),
      _hasMoreDiscoveryUsers,
    );
  }

  Future<
    ({
      List<DiscoveryResult> results,
      int storedCount,
      QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument,
      bool hasMore,
    })
  >
  _fetchStoredRecommendationsPage({
    GetOptions? options,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _usersRef
        .doc(currentUid)
        .collection(FirestoreCollections.recommendations)
        .orderBy('score', descending: true);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final blockedUidsFuture = _readBlockedUids(options: options);
    final snapshot = await query.limit(_pageSize).get(options);

    if (snapshot.docs.isEmpty) {
      return (
        results: const <DiscoveryResult>[],
        storedCount: 0,
        lastDocument: startAfter,
        hasMore: false,
      );
    }

    final recommendationDocs = snapshot.docs;

    final results = <DiscoveryResult>[];
    for (final doc in recommendationDocs) {
      final data = doc.data();
      final uid = (data['userId'] ?? doc.id).toString();
      if (uid.isEmpty || uid == currentUid) continue;
      final user = _userFromRecommendationSnapshot(uid: uid, data: data);
      if (user == null) continue;
      if (user.topArtistNames.isEmpty && user.topGenreNames.isEmpty) continue;

      results.add(
        _discoveryResultFromStoredRecommendation(user: user, data: data),
      );
    }

    try {
      final blockedUids = await blockedUidsFuture;
      if (blockedUids.isNotEmpty) {
        results.removeWhere((r) => blockedUids.contains(r.user.uid));
      }
    } catch (_) {
      // non-fatal: discovery proceeds without block filtering
    }

    return (
      results: results,
      storedCount: recommendationDocs.length,
      lastDocument: recommendationDocs.last,
      hasMore: recommendationDocs.length == _pageSize,
    );
  }

  AppUser? _userFromRecommendationSnapshot({
    required String uid,
    required Map<String, dynamic> data,
  }) {
    if (data['snapshotVersion'] != _recommendationSnapshotVersion) return null;
    final rawSnapshot = data['profileSnapshot'];
    if (rawSnapshot is! Map) return null;

    final snapshot = Map<String, dynamic>.from(rawSnapshot);
    if ((snapshot['displayName'] ?? '').toString().trim().isEmpty ||
        (snapshot['username'] ?? '').toString().trim().isEmpty) {
      return null;
    }
    return AppUser.fromMap(uid: uid, data: snapshot);
  }

  Future<Set<String>> _readBlockedUids({GetOptions? options}) async {
    final cached = _blockedUids;
    if (cached != null) return cached;

    try {
      final privateDoc = await _privateUsersRef.doc(currentUid).get(options);
      final blocked = Set<String>.from(
        (privateDoc.data()?['blockedUsers'] as List?)?.map(
              (value) => value.toString(),
            ) ??
            const <String>[],
      );
      _blockedUids = blocked;
      return blocked;
    } catch (_) {
      return const <String>{};
    }
  }

  Future<DiscoveryResult?> getStoredCompatibilityWith(AppUser otherUser) async {
    try {
      final doc = await _usersRef
          .doc(currentUid)
          .collection(FirestoreCollections.recommendations)
          .doc(otherUser.uid)
          .get();
      final data = doc.data();
      if (!doc.exists || data == null) return null;

      return _discoveryResultFromStoredRecommendation(
        user: otherUser,
        data: data,
      );
    } on FirebaseException catch (e, stack) {
      await reportError(e, stack);
      return null;
    } catch (_) {
      return null;
    }
  }

  DiscoveryResult _discoveryResultFromStoredRecommendation({
    required AppUser user,
    required Map<String, dynamic> data,
  }) {
    return DiscoveryResult(
      user: user,
      score: ((data['score'] as num?) ?? 0).toDouble(),
      sharedArtistNames:
          (data['sharedArtistNames'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
      sharedGenreNames:
          (data['sharedGenreNames'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
    );
  }

  Future<DiscoveryResult> getCompatibilityWith(
    AppUser myUser,
    AppUser otherUser,
  ) async {
    return MusicProfileService.calculateCompatibility(
      myArtistNames: myUser.topArtistNames,
      myArtistKeys: _effectiveArtistKeys(myUser),
      myGenreNames: myUser.topGenreNames,
      otherUser: otherUser.copyWith(
        topArtistKeys: _effectiveArtistKeys(otherUser),
      ),
    );
  }

  @visibleForTesting
  static DiscoveryResult calculateCompatibility({
    required List<String> myArtistNames,
    List<String> myArtistKeys = const [],
    required List<String> myGenreNames,
    required AppUser otherUser,
  }) {
    final myArtists = _uniqueArtistIdentities(
      myArtistNames.take(MusicProfileLimits.maxArtists).toList(growable: false),
      myArtistKeys,
    );
    final otherArtists = _uniqueArtistIdentities(
      otherUser.topArtistNames
          .take(MusicProfileLimits.maxArtists)
          .toList(growable: false),
      otherUser.topArtistKeys,
    );
    final myUniqueGenreNames = _uniqueGenreNames(myGenreNames);
    final otherUniqueGenreNames = _uniqueGenreNames(otherUser.topGenreNames);
    final myGenres = myUniqueGenreNames.map(_normalizedMusicKey).toSet();
    final usedMyArtistIndexes = <int>{};
    final sharedArtists = <String>[];
    for (final otherArtist in otherArtists) {
      var myArtistIndex = -1;
      for (var index = 0; index < myArtists.length; index++) {
        if (usedMyArtistIndexes.contains(index)) continue;
        if (_artistsMatch(myArtists[index], otherArtist)) {
          myArtistIndex = index;
          break;
        }
      }
      if (myArtistIndex < 0) continue;
      usedMyArtistIndexes.add(myArtistIndex);
      sharedArtists.add(otherArtist.name);
    }
    final sharedGenres = otherUniqueGenreNames
        .where((genre) => myGenres.contains(_normalizedMusicKey(genre)))
        .toList();

    final artistScore = _similarityScore(
      sharedCount: sharedArtists.length,
      leftCount: myArtists.length,
      rightCount: otherArtists.length,
      evidenceTarget: _artistEvidenceTarget,
      weight: _artistScoreWeight,
    );
    final genreScore = _similarityScore(
      sharedCount: sharedGenres.length,
      leftCount: myUniqueGenreNames.length,
      rightCount: otherUniqueGenreNames.length,
      evidenceTarget: _genreEvidenceTarget,
      weight: _genreScoreWeight,
    );

    return DiscoveryResult(
      user: otherUser,
      score: (artistScore + genreScore).roundToDouble(),
      sharedArtistNames: sharedArtists,
      sharedGenreNames: sharedGenres,
    );
  }

  static String _normalizedMusicKey(String value) => value.trim().toLowerCase();

  static List<String> _effectiveArtistKeys(AppUser user) {
    if (user.topArtists.length == user.topArtistNames.length &&
        user.topArtists.asMap().entries.every(
          (entry) =>
              normalizeArtistIdentityName(entry.value.name) ==
              normalizeArtistIdentityName(user.topArtistNames[entry.key]),
        )) {
      return artistIdentityKeys(user.topArtists);
    }
    return user.topArtistKeys;
  }

  static List<({String name, String key})> _uniqueArtistIdentities(
    List<String> names,
    List<String> keys,
  ) {
    final artistsByKey = <String, ({String name, String key})>{};
    for (var index = 0; index < names.length; index++) {
      final name = names[index].trim();
      if (name.isEmpty) continue;
      final storedKey = index < keys.length ? keys[index].trim() : '';
      final key = storedKey.isNotEmpty
          ? storedKey
          : artistIdentityKey(name: name);
      artistsByKey.putIfAbsent(key, () => (name: name, key: key));
    }
    return artistsByKey.values.toList(growable: false);
  }

  static bool _artistsMatch(
    ({String name, String key}) left,
    ({String name, String key}) right,
  ) {
    final leftHasSpotifyId = isSpotifyArtistIdentityKey(left.key);
    final rightHasSpotifyId = isSpotifyArtistIdentityKey(right.key);
    if (leftHasSpotifyId && rightHasSpotifyId) {
      return left.key == right.key;
    }
    return normalizeArtistIdentityName(left.name) ==
        normalizeArtistIdentityName(right.name);
  }

  static List<String> _uniqueGenreNames(List<String> values) =>
      normalizeGenreNames(values);

  static double _similarityScore({
    required int sharedCount,
    required int leftCount,
    required int rightCount,
    required double evidenceTarget,
    required double weight,
  }) {
    if (sharedCount == 0) return 0.0;

    final comparableCount = leftCount < rightCount ? leftCount : rightCount;
    final coverage = comparableCount == 0 ? 0.0 : sharedCount / comparableCount;
    final evidence = (sharedCount / evidenceTarget).clamp(0.0, 1.0);
    final similarity = coverage > evidence ? coverage : evidence;
    return similarity * weight;
  }
}
