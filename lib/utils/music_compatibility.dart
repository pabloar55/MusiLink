import 'package:flutter/foundation.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/discovery_result.dart';
import 'package:musi_link/utils/artist_identity.dart';
import 'package:musi_link/utils/genre_normalizer.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

// Mismos pesos y umbrales que `calculateRecommendation` en el backend.
const _artistScoreWeight = 70.0;
const _genreScoreWeight = 30.0;
const _artistEvidenceTarget = 7.0;
const _genreEvidenceTarget = 4.0;

/// Compatibilidad musical de [myUser] con [otherUser], calculada en local
/// cuando aún no hay una recomendación guardada.
DiscoveryResult compatibilityBetween(AppUser myUser, AppUser otherUser) {
  return calculateCompatibility(
    myArtistNames: myUser.topArtistNames,
    myArtistKeys: _effectiveArtistKeys(myUser),
    myGenreNames: myUser.topGenreNames,
    otherUser: otherUser.copyWith(
      topArtistKeys: _effectiveArtistKeys(otherUser),
    ),
  );
}

@visibleForTesting
DiscoveryResult calculateCompatibility({
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
  final myUniqueGenreNames = normalizeGenreNames(myGenreNames);
  final otherUniqueGenreNames = normalizeGenreNames(otherUser.topGenreNames);
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

String _normalizedMusicKey(String value) => value.trim().toLowerCase();

List<String> _effectiveArtistKeys(AppUser user) {
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

List<({String name, String key})> _uniqueArtistIdentities(
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

bool _artistsMatch(
  ({String name, String key}) left,
  ({String name, String key}) right,
) => artistIdentitiesMatch(
  leftName: left.name,
  leftKey: left.key,
  rightName: right.name,
  rightKey: right.key,
);

double _similarityScore({
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
