import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';

/// Reglas para leer las recomendaciones que genera el backend en
/// `functions/src/recommendations.ts`. Deben mantenerse alineadas con
/// `recommendationGenerationCovers` y con el formato del snapshot de perfil.

const _profileSnapshotVersion = 1;
const _recentRefreshRequestWindow = Duration(minutes: 2);

/// Si las recomendaciones guardadas aún no reflejan el último cambio del perfil
/// musical descrito por el documento de usuario [userData].
bool recommendationRefreshPending(Map<String, dynamic>? userData) {
  if (userData == null ||
      !userData.containsKey('recommendationsRefreshRequestedAt')) {
    return false;
  }

  final requestedVersion = userData['musicProfileVersion'];
  final generatedVersion =
      userData['recommendationsGeneratedForMusicProfileVersion'];
  if (requestedVersion is int) {
    return generatedVersion is! int || generatedVersion < requestedVersion;
  }

  final requestedAt = userData['recommendationsRefreshRequestedAt'];
  final generatedAt = userData['recommendationsGeneratedAt'];
  if (requestedAt is! Timestamp) {
    // A local serverTimestamp can temporarily resolve as null.
    return true;
  }
  return generatedAt is! Timestamp ||
      generatedAt.millisecondsSinceEpoch < requestedAt.millisecondsSinceEpoch;
}

/// Si merece la pena esperar a la regeneración pendiente: solo cuando se pidió
/// hace poco. Una petición antigua probablemente falló y no debe bloquear la
/// lectura del último estado disponible.
bool shouldAwaitRecommendationRefresh(
  Map<String, dynamic>? userData, {
  required DateTime now,
}) {
  if (!recommendationRefreshPending(userData)) return false;

  final requestedAt = userData?['recommendationsRefreshRequestedAt'];
  if (requestedAt is! Timestamp) return false;
  return now.difference(requestedAt.toDate()) < _recentRefreshRequestWindow;
}

/// Resultado de discovery de un documento de `recommendations`, o null si no se
/// puede mostrar: pertenece a [currentUid], su snapshot de perfil es de otra
/// versión o le falta el nombre, el username o datos musicales.
DiscoveryResult? discoveryResultFromStoredRecommendation({
  required String docId,
  required Map<String, dynamic> data,
  required String currentUid,
}) {
  final uid = (data['userId'] ?? docId).toString();
  if (uid.isEmpty || uid == currentUid) return null;
  if (data['snapshotVersion'] != _profileSnapshotVersion) return null;
  final rawSnapshot = data['profileSnapshot'];
  if (rawSnapshot is! Map) return null;

  final snapshot = Map<String, dynamic>.from(rawSnapshot);
  if ((snapshot['displayName'] ?? '').toString().trim().isEmpty ||
      (snapshot['username'] ?? '').toString().trim().isEmpty) {
    return null;
  }
  final user = AppUser.fromMap(uid: uid, data: snapshot);
  if (user == null) return null;
  if (user.topArtistNames.isEmpty && user.topGenreNames.isEmpty) return null;

  return DiscoveryResult.fromStoredRecommendation(user: user, data: data);
}
