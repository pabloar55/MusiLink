String userProfileLocation(String uid, {bool fromChat = false}) {
  return Uri(
    pathSegments: ['', 'profile', uid],
    queryParameters: fromChat ? const {'fromChat': 'true'} : null,
  ).toString();
}

/// Indica si [location] es la ruta de un enlace de perfil compartido
/// (`/u/:username`).
bool isUserProfileLinkLocation(String location) => location.startsWith('/u/');
