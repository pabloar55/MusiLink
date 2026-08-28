String userProfileLocation(String uid, {bool fromChat = false}) {
  return Uri(
    pathSegments: ['', 'profile', uid],
    queryParameters: fromChat ? const {'fromChat': 'true'} : null,
  ).toString();
}
