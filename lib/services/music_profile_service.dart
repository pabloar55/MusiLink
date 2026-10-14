import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/artist.dart' as app;
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/models/stored_recommendations.dart';
import 'package:musi_link/services/authenticated_service.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/utils/artist_identity.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

class BlockedUsersReadException implements Exception {
  const BlockedUsersReadException(this.cause);

  final Object cause;
}

class MusicProfileService with AuthenticatedService {
  MusicProfileService(
    this._musicCatalogService, {
    required this._firestore,
    required this._auth,
    required this._functions,
  });

  final MusicCatalogService _musicCatalogService;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

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
  int _cacheRevision = 0;

  void clearCache() {
    _cacheRevision++;
    _cachedResults = null;
    _cacheTime = null;
    _lastRecommendationDoc = null;
    _blockedUids = null;
    _hasMoreDiscoveryUsers = false;
  }

  static const _cacheTtl = Duration(minutes: 30);
  static const _recommendationGenerationWait = Duration(seconds: 15);
  static const _pageSize = 20;

  bool get hasMoreDiscoveryUsers => _hasMoreDiscoveryUsers;

  bool get _isCacheValid =>
      _cachedResults != null &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheTtl;

  List<DiscoveryResult> _cacheFirstPage(
    List<DiscoveryResult> results, {
    required QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument,
    required bool hasMore,
    required int revision,
  }) {
    if (revision != _cacheRevision) {
      return List<DiscoveryResult>.unmodifiable(results);
    }
    _cachedResults = results;
    _cacheTime = DateTime.now();
    _lastRecommendationDoc = lastDocument;
    _hasMoreDiscoveryUsers = hasMore;
    return List<DiscoveryResult>.unmodifiable(results);
  }

  Future<void> saveManualArtists(List<app.Artist> selectedArtists) async {
    try {
      // Fail before catalog hydration when the session has already expired.
      final uid = currentUid;
      final artists = await _hydrateMissingArtistDetails(
        selectedArtists.take(MusicProfileLimits.maxArtists).toList(),
      );
      if (currentUid != uid) {
        throw StateError('Account changed while preparing artists.');
      }
      final callable = _functions.httpsCallable('saveMusicProfile');
      await callable.call<void>({
        'artists': artists.map((artist) => artist.toMap()).toList(),
      });
      clearCache();
    } catch (e, stack) {
      if (!isRateLimitError(e)) await reportError(e, stack);
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
      // Un homónimo con otro spotifyId es otro artista: completarlo con él
      // cambiaría la identidad elegida y podría duplicar otra del perfil.
      if (_normalizedMusicKey(enriched.name) !=
              _normalizedMusicKey(artist.name) ||
          !isSameArtist(enriched, artist)) {
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
    final revision = _cacheRevision;
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
      if (recommendationRefreshPending(myDoc.data())) return null;

      _blockedUids = null;
      final stored = await _fetchStoredRecommendationsPage(options: opts);
      if (revision != _cacheRevision) return null;
      final recommendationCount = myDoc.data()?['recommendationsCount'] as int?;
      if (stored.storedCount == 0 && recommendationCount != 0) return null;

      return _cacheFirstPage(
        stored.results,
        lastDocument: stored.lastDocument,
        hasMore: stored.hasMore,
        revision: revision,
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
    final revision = _cacheRevision;
    try {
      _blockedUids = null;
      var myDoc = await _usersRef.doc(currentUid).get();
      if (!myDoc.exists) {
        return _cacheFirstPage(
          const [],
          lastDocument: null,
          hasMore: false,
          revision: revision,
        );
      }
      if (shouldAwaitRecommendationRefresh(myDoc.data(), now: DateTime.now())) {
        myDoc = await _waitForRecommendationRefresh(myDoc);
      }

      final myUser = AppUser.fromFirestore(myDoc);
      if (myUser == null) {
        return _cacheFirstPage(
          const [],
          lastDocument: null,
          hasMore: false,
          revision: revision,
        );
      }
      if (myUser.topArtistNames.isEmpty && myUser.topGenreNames.isEmpty) {
        return _cacheFirstPage(
          const [],
          lastDocument: null,
          hasMore: false,
          revision: revision,
        );
      }

      final stored = await _fetchStoredRecommendationsPage();
      return _cacheFirstPage(
        stored.results,
        lastDocument: stored.lastDocument,
        hasMore: stored.hasMore,
        revision: revision,
      );
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
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
                !recommendationRefreshPending(snapshot.data()),
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
    final revision = _cacheRevision;
    if (_cachedResults == null || !_hasMoreDiscoveryUsers) {
      return (
        List<DiscoveryResult>.unmodifiable(_cachedResults ?? const []),
        false,
      );
    }

    final stored = await _fetchStoredRecommendationsPage(
      startAfter: _lastRecommendationDoc,
    );
    if (revision != _cacheRevision) {
      return (
        List<DiscoveryResult>.unmodifiable(_cachedResults ?? const []),
        _hasMoreDiscoveryUsers,
      );
    }
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

    final blockedUids = await _readBlockedUids(options: options);
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
      final result = discoveryResultFromStoredRecommendation(
        docId: doc.id,
        data: doc.data(),
        currentUid: currentUid,
      );
      if (result != null) results.add(result);
    }

    if (blockedUids.isNotEmpty) {
      results.removeWhere((r) => blockedUids.contains(r.user.uid));
    }

    return (
      results: results,
      storedCount: recommendationDocs.length,
      lastDocument: recommendationDocs.last,
      hasMore: recommendationDocs.length == _pageSize,
    );
  }

  Future<Set<String>> _readBlockedUids({GetOptions? options}) async {
    final cached = _blockedUids;
    if (cached != null) return cached;
    final revision = _cacheRevision;

    try {
      final privateDoc = await _privateUsersRef.doc(currentUid).get(options);
      final blocked = Set<String>.from(
        (privateDoc.data()?['blockedUsers'] as List?)?.map(
              (value) => value.toString(),
            ) ??
            const <String>[],
      );
      if (revision == _cacheRevision) _blockedUids = blocked;
      return blocked;
    } catch (error) {
      throw BlockedUsersReadException(error);
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

      return DiscoveryResult.fromStoredRecommendation(
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

  static String _normalizedMusicKey(String value) => value.trim().toLowerCase();
}
