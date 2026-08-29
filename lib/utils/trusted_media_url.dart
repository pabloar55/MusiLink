final RegExp _spotifyImageUrl = RegExp(
  r'^https://i[.]scdn[.]co/image/[A-Za-z0-9]+$',
);

final RegExp _profilePhotoUrl = RegExp(
  r'^https://firebasestorage[.]googleapis[.]com/v0/b/'
  r'musi-link-e7759[.]firebasestorage[.]app/o/'
  r'profile_photos%2F[A-Za-z0-9]{1,128}'
  r'[?]alt=media&token=[A-Za-z0-9_-]{1,256}$',
);

/// Returns [value] only when it is an image served by Spotify's image CDN.
String trustedSpotifyImageUrl(String value) =>
    _spotifyImageUrl.hasMatch(value) ? value : '';

/// Returns [value] only when it points to a profile photo in MusiLink's bucket.
/// Firestore Rules additionally bind the object path to the profile owner's UID.
String trustedProfilePhotoUrl(String value) {
  final trimmed = value.trim();
  return _profilePhotoUrl.hasMatch(trimmed) ? trimmed : '';
}
