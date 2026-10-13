import 'dart:collection';

import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/services/user_service.dart';

class _CachedUser {
  final AppUser? user;
  final DateTime _cachedAt;

  _CachedUser(this.user) : _cachedAt = DateTime.now();

  bool isExpired(Duration ttl) => DateTime.now().difference(_cachedAt) > ttl;
}

/// Mixin que memoiza la carga de perfiles de usuario para evitar
/// reiniciar el FutureBuilder en cada build.
///
/// Cachea el valor resuelto (no el Future) con un TTL de [cacheTtl].
/// Pasado ese tiempo, o tras llamar a [invalidateUserFuture], se hace
/// una nueva petición a Firestore.
///
/// Implementa LRU con tamaño máximo [_maxCacheSize] para evitar
/// crecimiento ilimitado en sesiones largas (p.ej. scroll infinito).
mixin UserFutureCache {
  static const int _maxCacheSize = 100;

  // LinkedHashMap mantiene orden de inserción: el primer elemento
  // es siempre el menos recientemente usado (LRU).
  final LinkedHashMap<String, _CachedUser> _userCache = LinkedHashMap();
  final Map<String, Future<AppUser?>> _pendingUserFutures = {};

  /// TTL del caché. Sobreescribir para ajustar por pantalla.
  Duration get cacheTtl => const Duration(minutes: 5);

  /// Las clases que usen este mixin deben implementar este getter
  /// para proporcionar la instancia de UserService vía Riverpod.
  UserService get userService;

  Future<AppUser?> getUserFuture(String uid) {
    if (uid.isEmpty) return Future.value();

    final cached = _userCache[uid];
    if (cached != null && !cached.isExpired(cacheTtl)) {
      // Mover al final para marcarlo como el más recientemente usado.
      _userCache
        ..remove(uid)
        ..[uid] = cached;
      return Future.value(cached.user);
    }

    final pending = _pendingUserFutures[uid];
    if (pending != null) return pending;

    late final Future<AppUser?> request;
    request = userService
        .getUser(uid)
        .then((user) {
          _userCache.remove(uid); // Eliminar entrada expirada si existía.
          _evictIfNeeded();
          _userCache[uid] = _CachedUser(user);
          return user;
        })
        .whenComplete(() {
          if (identical(_pendingUserFutures[uid], request)) {
            _pendingUserFutures.remove(uid);
          }
        });
    _pendingUserFutures[uid] = request;
    return request;
  }

  void _evictIfNeeded() {
    while (_userCache.length >= _maxCacheSize) {
      _userCache.remove(_userCache.keys.first);
    }
  }

  void invalidateUserFuture(String uid) {
    _userCache.remove(uid);
    _pendingUserFutures.remove(uid);
  }
}
