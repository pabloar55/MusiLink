import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/friend_service.dart';

final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final authUser =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser;
  if (authUser == null) return Stream.value(null);
  return ref.watch(userServiceProvider).watchUser(authUser.uid);
});

final userStreamProvider = StreamProvider.family<AppUser?, String>((ref, uid) {
  return ref.read(userServiceProvider).watchUser(uid);
});

/// Resuelve el uid de un username para los enlaces de perfil `/u/:username`.
final uidByUsernameProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, username) {
      return ref.read(userServiceProvider).getUidByUsername(username);
    });

final compatibilityProvider = FutureProvider.family<DiscoveryResult, AppUser>((
  ref,
  user,
) async {
  final myUser = await ref.watch(currentUserProvider.future);
  if (myUser == null) {
    return DiscoveryResult(
      user: user,
      score: 0,
      sharedArtistNames: [],
      sharedGenreNames: [],
    );
  }
  final service = ref.read(musicProfileServiceProvider);
  final storedResult = await service.getStoredCompatibilityWith(user);
  if (storedResult != null) return storedResult;

  return service.getCompatibilityWith(myUser, user);
});

final relationshipProvider = StreamProvider.family<RelationshipResult, String>((
  ref,
  userUid,
) {
  return ref.read(friendServiceProvider).watchRelationship(userUid);
});
