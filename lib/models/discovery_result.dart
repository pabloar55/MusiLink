import 'package:musi_link/models/app_user.dart';

class DiscoveryResult {
  final AppUser user;
  final double score;
  final List<String> sharedArtistNames;
  final List<String> sharedGenreNames;

  const DiscoveryResult({
    required this.user,
    required this.score,
    required this.sharedArtistNames,
    required this.sharedGenreNames,
  });

  /// Puntuación y coincidencias guardadas por el backend para [user].
  factory DiscoveryResult.fromStoredRecommendation({
    required AppUser user,
    required Map<String, dynamic> data,
  }) {
    return DiscoveryResult(
      user: user,
      score: ((data['score'] as num?) ?? 0).toDouble(),
      sharedArtistNames: _stringList(data['sharedArtistNames']),
      sharedGenreNames: _stringList(data['sharedGenreNames']),
    );
  }

  static List<String> _stringList(Object? value) =>
      (value as List<dynamic>?)?.map((item) => item.toString()).toList() ??
      const [];
}
