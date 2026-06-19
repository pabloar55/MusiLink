import 'package:cloud_functions/cloud_functions.dart';
import 'package:musi_link/models/artist.dart' as app;
import 'package:musi_link/models/track.dart' as app;
import 'package:musi_link/utils/error_reporter.dart';

class SpotifyCloudService {
  SpotifyCloudService(this._functions);

  final FirebaseFunctions _functions;

  Future<List<app.Artist>> searchArtists(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    try {
      final callable = _functions.httpsCallable('searchSpotifyArtists');
      final result = await callable.call<List<dynamic>>({'query': query, 'limit': limit});
      return result.data.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        return app.Artist(
          name: item['name'] as String? ?? 'Unknown Artist',
          imageUrl: item['imageUrl'] as String? ?? '',
          genres: List<String>.from(item['genres'] as List? ?? []),
          spotifyId: item['spotifyId'] as String?,
        );
      }).toList();
    } catch (e, stack) {
      await reportError(e, stack);
      return [];
    }
  }

  Future<List<app.Track>> searchTracks(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    try {
      final callable = _functions.httpsCallable('searchSpotifyTracks');
      final result = await callable.call<List<dynamic>>({'query': query, 'limit': limit});
      return result.data.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        return app.Track(
          title: item['title'] as String? ?? 'Unknown',
          artist: item['artist'] as String? ?? 'Unknown Artist',
          imageUrl: item['imageUrl'] as String? ?? '',
          spotifyUrl: item['spotifyUrl'] as String? ?? '',
        );
      }).toList();
    } catch (e, stack) {
      await reportError(_spotifySearchError('searchSpotifyTracks', e), stack);
      return [];
    }
  }
}

Object _spotifySearchError(String operation, Object error) {
  if (error is! FirebaseFunctionsException) return error;

  return StateError(
    '$operation failed: code=${error.code}, '
    'message=${error.message ?? ''}, details=${error.details ?? ''}',
  );
}
