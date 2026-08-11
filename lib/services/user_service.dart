import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/utils/firestore_collections.dart';

/// El username solicitado ya pertenece a otro usuario.
class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}

/// Servicio para gestionar perfiles de usuario en Firestore.
class UserService {
  UserService({
    required FirebaseFirestore firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functions;
  late final CollectionReference<Map<String, dynamic>> _usersRef = _firestore
      .collection(FirestoreCollections.users);
  late final CollectionReference<Map<String, dynamic>> _usernamesRef =
      _firestore.collection(FirestoreCollections.usernames);
  late final CollectionReference<Map<String, dynamic>> _privateUsersRef =
      _firestore.collection(FirestoreCollections.userPrivate);
  static const int _maxCacheSize = 200;
  static final RegExp _validUsername = RegExp(r'^[a-z0-9_]{3,20}$');
  static const _userCacheTtl = Duration(minutes: 10);
  final LinkedHashMap<String, ({AppUser user, DateTime cachedAt})> _userCache =
      LinkedHashMap();
  final Map<String, Future<AppUser?>> _pendingUserRequests = {};
  final Map<String, Future<List<AppUser>>> _pendingUserListRequests = {};

  void clearCache() => _userCache.clear();

  /// Reserva el username y crea el perfil mediante una callable transaccional.
  Future<void> createUserProfile({
    required String displayName,
    required String username,
  }) async {
    final functions = _functions;
    if (functions == null) {
      throw StateError(
        'FirebaseFunctions is required to create a user profile.',
      );
    }

    try {
      final callable = functions.httpsCallable('createUserProfile');
      await callable.call<void>({
        'displayName': displayName.trim(),
        'username': normalizeUsername(username),
      });
    } on FirebaseFunctionsException catch (e, stack) {
      if (e.code == 'already-exists') {
        throw const UsernameAlreadyTakenException();
      }
      await reportError(e, stack);
      rethrow;
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Stream en tiempo real del perfil de un usuario.
  Stream<AppUser?> watchUser(String uid) {
    return _usersRef
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromFirestore(doc) : null);
  }

  /// Obtiene el perfil de un usuario por su UID.
  /// Resultado cacheado en memoria por [_userCacheTtl] para evitar reads
  /// repetidas desde discovery, chats y amigos.
  Future<AppUser?> getUser(
    String uid, {
    bool reportErrors = true,
    bool bypassCache = false,
  }) {
    if (!bypassCache) {
      final cached = _getFromCache(uid);
      if (cached != null) {
        return Future.value(cached.user);
      }

      final pending = _pendingUserRequests[uid];
      if (pending != null) return pending;
    }

    late final Future<AppUser?> request;
    request = _fetchUser(uid, reportErrors: reportErrors).whenComplete(() {
      if (identical(_pendingUserRequests[uid], request)) {
        _pendingUserRequests.remove(uid);
      }
    });
    if (!bypassCache) _pendingUserRequests[uid] = request;
    return request;
  }

  Future<AppUser?> _fetchUser(String uid, {required bool reportErrors}) async {
    try {
      final doc = await _usersRef.doc(uid).get();
      if (!doc.exists) return null;
      final user = AppUser.fromFirestore(doc);
      if (user != null) {
        _addToCache(uid, user);
      }
      return user;
    } catch (e, stack) {
      if (reportErrors) {
        await reportError(e, stack);
      }
      rethrow;
    }
  }

  ({AppUser user, DateTime cachedAt})? _getFromCache(String uid) {
    final cached = _userCache[uid];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.cachedAt) >= _userCacheTtl) {
      _userCache.remove(uid);
      return null;
    }

    _userCache
      ..remove(uid)
      ..[uid] = cached;
    return cached;
  }

  void _addToCache(String uid, AppUser user) {
    _userCache.remove(uid);
    while (_userCache.length >= _maxCacheSize) {
      _userCache.remove(_userCache.keys.first);
    }
    _userCache[uid] = (user: user, cachedAt: DateTime.now());
  }

  /// Comprueba si un usuario existe en Firestore.
  Future<bool> userExists(String uid) async {
    try {
      final doc = await _usersRef.doc(uid).get();
      return doc.exists;
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Comprueba si un username ya está en uso.
  Future<bool> usernameExists(String username) async {
    final normalized = normalizeUsername(username);
    if (!_validUsername.hasMatch(normalized) ||
        normalized == AppUser.deletedUsername) {
      return true;
    }

    try {
      final reservation = await _usernamesRef.doc(normalized).get();
      return reservation.exists;
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  static String normalizeUsername(String username) =>
      username.trim().toLowerCase();

  /// Actualiza la fecha de último login.
  Future<void> updateLastLogin(String uid) async {
    try {
      await _privateUsersRef.doc(uid).update({
        'lastLogin': Timestamp.fromDate(DateTime.now()),
      });
      _userCache.remove(uid);
    } catch (e, stack) {
      await reportError(e, stack);
    }
  }

  /// Actualiza campos del perfil de usuario.
  Future<void> updateProfile(
    String uid, {
    String? displayName,
    String? photoUrl,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (displayName != null) {
        updates['displayName'] = displayName;
      }
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      if (updates.isNotEmpty) {
        await _usersRef.doc(uid).update(updates);
        _userCache.remove(uid);
      }
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Busca usuarios por username.
  /// Excluye al usuario con [excludeUid] de los resultados. (el que hace la búsqueda)
  Future<List<AppUser>> searchUsers(String query, {String? excludeUid}) async {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return [];

    try {
      final snapshot = await _usersRef
          .where('username', isGreaterThanOrEqualTo: lowerQuery)
          .where('username', isLessThanOrEqualTo: '$lowerQuery')
          .limit(20)
          .get();

      return snapshot.docs
          .map(AppUser.fromFirestore)
          .whereType<AppUser>()
          .where((u) => u.uid != excludeUid)
          .toList();
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Establece la canción del día del usuario.
  Future<void> setDailySong(String uid, Track track) async {
    try {
      await _usersRef.doc(uid).update({
        'dailySong': track.toMap(),
        // Server time keeps the 24-hour window independent from the device
        // clock and is also the timestamp used by the expiry job.
        'dailySongUpdatedAt': FieldValue.serverTimestamp(),
      });
      _userCache.remove(uid);
    } catch (e, stack) {
      await reportError(e, stack);
    }
  }

  /// Anonimiza el perfil de [uid] eliminando todos los datos personales.
  /// El documento se mantiene para que los mensajes existentes sigan teniendo
  /// un autor reconocible ("Deleted user") en lugar de romperse.
  Future<void> anonymizeUser(String uid) async {
    try {
      final publicProfile = await _usersRef.doc(uid).get();
      final username = normalizeUsername(
        (publicProfile.data()?['username'] ?? '').toString(),
      );
      final pushTokens = await _privateUsersRef
          .doc(uid)
          .collection(FirestoreCollections.pushTokens)
          .get();
      final reservation =
          username.isNotEmpty && username != AppUser.deletedUsername
          ? await _usernamesRef.doc(username).get()
          : null;
      final batch = _firestore.batch();
      batch.update(_usersRef.doc(uid), {
        'displayName': AppUser.deletedDisplayName,
        'username': AppUser.deletedUsername,
        'photoUrl': '',
        'spotifyId': FieldValue.delete(),
        'topArtists': FieldValue.delete(),
        'topGenres': FieldValue.delete(),
        'topArtistNames': FieldValue.delete(),
        'topArtistKeys': FieldValue.delete(),
        'topGenreNames': FieldValue.delete(),
        'artistIdentityVersion': FieldValue.delete(),
        'dailySong': FieldValue.delete(),
        'dailySongUpdatedAt': FieldValue.delete(),
      });
      for (final token in pushTokens.docs) {
        batch.delete(token.reference);
      }
      if (reservation?.data()?['uid'] == uid) {
        batch.delete(reservation!.reference);
      }
      batch.delete(_privateUsersRef.doc(uid));
      await batch.commit();
      _userCache.remove(uid);
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }

  /// Obtiene los usuarios correspondientes a una lista de UIDs.
  ///
  /// Conserva el orden original, reutiliza perfiles ya cacheados y agrupa en
  /// una sola petición las llamadas concurrentes para la misma lista.
  Future<List<AppUser>> getUsersByIds(List<String> uids) {
    final uniqueUids = uids
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueUids.isEmpty) return Future.value(const []);

    final requestKey = uniqueUids.join('\u0000');
    final pending = _pendingUserListRequests[requestKey];
    if (pending != null) return pending;

    late final Future<List<AppUser>> request;
    request = _fetchUsersByIds(uniqueUids).whenComplete(() {
      if (identical(_pendingUserListRequests[requestKey], request)) {
        _pendingUserListRequests.remove(requestKey);
      }
    });
    _pendingUserListRequests[requestKey] = request;
    return request;
  }

  Future<List<AppUser>> _fetchUsersByIds(List<String> uids) async {
    try {
      final usersById = <String, AppUser>{};
      final missingUids = <String>[];
      for (final uid in uids) {
        final cached = _getFromCache(uid);
        if (cached != null) {
          usersById[uid] = cached.user;
        } else {
          missingUids.add(uid);
        }
      }

      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var i = 0; i < missingUids.length; i += 10) {
        final chunk = missingUids.sublist(
          i,
          (i + 10).clamp(0, missingUids.length),
        );
        futures.add(
          _usersRef.where(FieldPath.documentId, whereIn: chunk).get(),
        );
      }
      final snapshots = await Future.wait(futures);
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          final user = AppUser.fromFirestore(doc);
          if (user == null) continue;
          usersById[user.uid] = user;
          _addToCache(user.uid, user);
        }
      }

      return [for (final uid in uids) ?usersById[uid]];
    } catch (e, stack) {
      await reportError(e, stack);
      rethrow;
    }
  }
}
