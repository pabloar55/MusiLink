class Artist {
  final String name;
  final String imageUrl;
  final List<String> genres;
  final String? spotifyId;

  const Artist({
    required this.name,
    required this.imageUrl,
    required this.genres,
    this.spotifyId,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as List<dynamic>?;
    final genresList = json['genres'] as List<dynamic>?;

    return Artist(
      name: (json['name'] ?? 'Artista desconocido').toString(),
      imageUrl: (images != null && images.isNotEmpty)
          ? ((images[0] as Map<String, dynamic>)['url'] ?? '').toString()
          : '',
      genres: genresList?.map((g) => g.toString()).toList() ?? [],
    );
  }

  factory Artist.fromMap(Map<String, dynamic> map) => Artist(
    name: (map['name'] ?? '').toString(),
    imageUrl: (map['imageUrl'] ?? '').toString(),
    genres:
        (map['genres'] as List<dynamic>?)?.map((g) => g.toString()).toList() ??
        [],
    spotifyId: map['spotifyId']?.toString(),
  );

  /// Parses untrusted persisted data without throwing.
  ///
  /// Unlike [fromMap], this rejects an artist when one of its structured
  /// fields has the wrong type so a single malformed profile entry cannot
  /// break every consumer of the containing user document.
  static Artist? tryFromMap(Object? value) {
    if (value is! Map) return null;

    final name = value['name'];
    final imageUrl = value['imageUrl'];
    final rawGenres = value['genres'];
    final spotifyId = value['spotifyId'];
    if (name is! String || name.trim().isEmpty) return null;
    if (imageUrl != null && imageUrl is! String) return null;
    if (rawGenres != null && rawGenres is! List) return null;
    if (spotifyId != null && spotifyId is! String) return null;

    final genres = <String>[];
    if (rawGenres is List) {
      for (final genre in rawGenres) {
        if (genre is! String) return null;
        final trimmed = genre.trim();
        if (trimmed.isNotEmpty) genres.add(trimmed);
      }
    }

    return Artist(
      name: name.trim(),
      imageUrl: (imageUrl as String?)?.trim() ?? '',
      genres: genres,
      spotifyId: spotifyId is String && spotifyId.trim().isNotEmpty
          ? spotifyId.trim()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'imageUrl': imageUrl,
    'genres': genres,
    if (spotifyId != null) 'spotifyId': spotifyId,
  };
}
