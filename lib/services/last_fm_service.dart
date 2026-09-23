import 'package:cloud_functions/cloud_functions.dart';
import 'package:musi_link/models/artist.dart' as app;

class LastFmService {
  LastFmService(this._functions);

  final FirebaseFunctions _functions;

  Future<List<app.Artist>> getSimilarArtists(
    String artistName, {
    int limit = 10,
  }) async {
    if (artistName.trim().isEmpty) return [];
    // Preserve failures so the catalog and screen do not cache them as empty.
    final callable = _functions.httpsCallable('getSimilarArtists');
    final result = await callable.call<List<dynamic>>({
      'artistName': artistName,
      'limit': limit,
    });
    return result.data
        .map(
          (dynamic name) => app.Artist(
            name: name as String? ?? 'Unknown',
            imageUrl: '',
            genres: const [],
          ),
        )
        .toList();
  }
}
