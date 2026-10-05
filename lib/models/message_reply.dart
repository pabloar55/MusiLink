/// Cita del mensaje al que responde otro mensaje del mismo chat.
class MessageReply {
  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.text,
    this.isTrack = false,
  });

  /// Mismo límite que aplica el backend al generar la cita.
  static const maxPreviewChars = 200;

  final String messageId;
  final String senderId;
  final String text;
  final bool isTrack;

  static String preview(String text) =>
      String.fromCharCodes(text.runes.take(maxPreviewChars));

  static MessageReply? tryFromMap(Object? value) {
    if (value is! Map ||
        value['messageId'] is! String ||
        (value['messageId'] as String).isEmpty ||
        value['senderId'] is! String) {
      return null;
    }
    return MessageReply(
      messageId: value['messageId'] as String,
      senderId: value['senderId'] as String,
      text: value['text'] is String ? value['text'] as String : '',
      isTrack: value['type'] == 'track',
    );
  }

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderId': senderId,
    'text': text,
    'type': isTrack ? 'track' : 'text',
  };
}
