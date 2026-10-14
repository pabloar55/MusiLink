import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/utils/firestore_collections.dart';
import 'package:musi_link/utils/user_setup_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resuelve y persiste los pasos del alta de una cuenta a partir de su perfil,
/// el trabajo de eliminación pendiente y la caché local.
class UserSetupRepository {
  UserSetupRepository({
    required this._firestore,
    required this._userService,
    required this._prefs,
  });

  final FirebaseFirestore _firestore;
  final UserService _userService;
  final SharedPreferences _prefs;

  static const _serverTimeout = Duration(seconds: 5);

  /// Lee solo datos locales para no retrasar la primera pantalla. La consulta
  /// al servidor se hace después con [fetch].
  Future<UserSetupBootstrapState> loadBootstrapState(String? uid) async {
    final cachedSetup = uid == null ? null : UserSetupCache.read(_prefs, uid);
    bool usernameSet = cachedSetup?.usernameSet ?? false;
    bool artistsSelected = cachedSetup?.artistsSelected ?? false;
    bool onboardingDone = cachedSetup?.onboardingDone ?? false;
    bool photoSetupDone = cachedSetup?.photoSetupDone ?? false;
    bool deletionPending = false;
    bool setupStateKnown = uid == null || cachedSetup != null;

    if (uid != null) {
      try {
        final user = await _userService.getSetupUser(uid, cacheOnly: true);
        usernameSet = user != null && user.username.isNotEmpty;
        artistsSelected = user != null && user.topArtistNames.isNotEmpty;
        final resolved = UserSetupCache.resolve(
          _prefs,
          uid,
          usernameSet: usernameSet,
          artistsSelected: artistsSelected,
        );
        onboardingDone = resolved.onboardingDone;
        photoSetupDone = resolved.photoSetupDone;
        setupStateKnown = true;
      } catch (_) {
        // Sin documento local se conserva el último snapshot persistido. La
        // consulta de servidor se hará después de pintar la primera pantalla.
      }

      try {
        final deletionJob = await _deletionJob(uid)
            .get(const GetOptions(source: Source.cache));
        deletionPending = deletionJob.exists;
      } catch (_) {}
    }

    if (uid != null && setupStateKnown) {
      await UserSetupCache.write(
        _prefs,
        uid,
        CachedUserSetupState(
          usernameSet: usernameSet,
          artistsSelected: artistsSelected,
          onboardingDone: onboardingDone,
          photoSetupDone: photoSetupDone,
        ),
      );
    }

    return UserSetupBootstrapState(
      usernameSet: usernameSet,
      artistsSelected: artistsSelected,
      onboardingDone: onboardingDone,
      photoSetupDone: photoSetupDone,
      deletionPending: deletionPending,
      setupStateKnown: setupStateKnown,
      userUid: uid,
    );
  }

  UserSetupState? readCached(String uid) {
    final cached = UserSetupCache.read(_prefs, uid);
    if (cached == null) return null;
    return (
      usernameSet: cached.usernameSet,
      artistsSelected: cached.artistsSelected,
      onboardingDone: cached.onboardingDone,
      photoSetupDone: cached.photoSetupDone,
      deletionPending: null,
    );
  }

  /// Consulta el servidor. Lanza una excepción si el perfil no está
  /// disponible; un fallo de red nunca equivale a una cuenta nueva.
  Future<UserSetupState> fetch(String uid) async {
    final deletionPendingFuture = _fetchDeletionPending(uid);
    final profile = await _userService
        .getSetupUser(uid, serverOnly: true)
        .timeout(_serverTimeout);
    final hasUsername = profile != null && profile.username.isNotEmpty;
    final hasArtists = profile != null && profile.topArtistNames.isNotEmpty;
    final setup = UserSetupCache.resolve(
      _prefs,
      uid,
      usernameSet: hasUsername,
      artistsSelected: hasArtists,
    );
    return (
      usernameSet: hasUsername,
      artistsSelected: hasArtists,
      onboardingDone: setup.onboardingDone,
      photoSetupDone: setup.photoSetupDone,
      deletionPending: await deletionPendingFuture,
    );
  }

  Future<void> persist(String uid, UserSetupState state) =>
      UserSetupCache.write(
        _prefs,
        uid,
        CachedUserSetupState(
          usernameSet: state.usernameSet,
          artistsSelected: state.artistsSelected,
          onboardingDone: state.onboardingDone,
          photoSetupDone: state.photoSetupDone,
        ),
      );

  Future<bool?> _fetchDeletionPending(String uid) async {
    try {
      final deletionJob = await _deletionJob(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(_serverTimeout);
      return deletionJob.exists;
    } catch (_) {
      // La disponibilidad de esta comprobación no invalida el perfil.
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>> _deletionJob(String uid) =>
      _firestore.collection(FirestoreCollections.accountDeletions).doc(uid);
}
