/// Reference to the publication answered by a chat message.
class DailySongReply {
  const DailySongReply({
    required this.ownerId,
    required this.publishedAtMicros,
    this.formatVersion = 2,
  });

  final String ownerId;
  final int publishedAtMicros;
  final int formatVersion;

  static DailySongReply? tryFromMap(Object? value) {
    if (value is! Map ||
        value['ownerId'] is! String ||
        (value['ownerId'] as String).isEmpty ||
        value['publishedAtMicros'] is! int) {
      return null;
    }
    return DailySongReply(
      ownerId: value['ownerId'] as String,
      publishedAtMicros: value['publishedAtMicros'] as int,
      formatVersion: value['formatVersion'] is int
          ? value['formatVersion'] as int
          : 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'ownerId': ownerId,
    'publishedAtMicros': publishedAtMicros,
    'formatVersion': formatVersion,
  };
}
