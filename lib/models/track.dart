class Track {
  final String title;
  final String artist;
  final String imageUrl;
  final String spotifyUrl;

  const Track({
    required this.title,
    required this.artist,
    required this.imageUrl,
    this.spotifyUrl = '',
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    final artists = json['artists'] as List<dynamic>?;
    final images =
        (json['album'] as Map<String, dynamic>?)?['images'] as List<dynamic>?;
    final trackId = (json['id'] ?? '').toString();

    return Track(
      title: (json['name'] ?? 'Sin título').toString(),
      artist: (artists != null && artists.isNotEmpty)
          ? ((artists[0] as Map<String, dynamic>)['name'] ??
                    'Artista desconocido')
                .toString()
          : 'Artista desconocido',
      imageUrl: (images != null && images.isNotEmpty)
          ? ((images[0] as Map<String, dynamic>)['url'] ?? '').toString()
          : '',
      spotifyUrl: trackId.isNotEmpty
          ? 'https://open.spotify.com/track/$trackId'
          : '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'artist': artist,
      'imageUrl': imageUrl,
      'spotifyUrl': spotifyUrl,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      title: (map['title'] ?? '').toString(),
      artist: (map['artist'] ?? '').toString(),
      imageUrl: (map['imageUrl'] ?? '').toString(),
      spotifyUrl: (map['spotifyUrl'] ?? '').toString(),
    );
  }

  /// Parses an untrusted Firestore value without relying on runtime casts.
  static Track? tryFromMap(Object? value) {
    if (value is! Map) return null;
    final title = value['title'];
    final artist = value['artist'];
    final imageUrl = value['imageUrl'];
    final spotifyUrl = value['spotifyUrl'];
    if (title is! String ||
        artist is! String ||
        imageUrl is! String ||
        spotifyUrl is! String) {
      return null;
    }
    return Track(
      title: title,
      artist: artist,
      imageUrl: imageUrl,
      spotifyUrl: spotifyUrl,
    );
  }
}
