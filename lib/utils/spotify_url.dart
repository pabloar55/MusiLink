final RegExp _canonicalSpotifyTrackUrl = RegExp(
  r'^https://open[.]spotify[.]com/track/[A-Za-z0-9]{22}$',
);

/// Returns a Spotify track URI only when [value] uses the canonical host,
/// path and 22-character base62 track ID emitted by searchSpotifyTracks.
Uri? parseSpotifyTrackUri(String value) {
  if (!_canonicalSpotifyTrackUrl.hasMatch(value)) return null;
  return Uri.tryParse(value);
}
