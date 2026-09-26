int safariMajorVersionFromUserAgent(String userAgent) {
  final match = RegExp(r'\bVersion/(\d+)').firstMatch(userAgent);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}
