import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:musi_link/models/track.dart';

/// Tipo de mensaje: texto normal o canción compartida.
enum MessageType { text, track }

/// Modelo que representa un mensaje dentro de un chat.
class Message {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool read;
  final bool delivered;

  /// Mensaje local pendiente de aparecer en Firestore.
  final bool isPending;
  final MessageType type;
  final Track? trackData;
  final Map<String, List<String>> reactions; // emoji -> lista de uids

  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.read = false,
    this.delivered = false,
    this.isPending = false,
    this.type = MessageType.text,
    this.trackData,
    this.reactions = const {},
  });

  bool get isTrack => type == MessageType.track;

  static Message? fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;

    final typeStr = (data['type'] ?? 'text').toString();
    final type = typeStr == 'track' ? MessageType.track : MessageType.text;

    Track? trackData;
    if (data['trackData'] is Map<String, dynamic>) {
      trackData = Track.fromMap(data['trackData'] as Map<String, dynamic>);
    }

    final reactionsRaw = data['reactions'] as Map<String, dynamic>? ?? {};
    final reactions = reactionsRaw.map(
      (key, value) => MapEntry(key, List<String>.from(value as List)),
    );

    return Message(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      read: (data['read'] as bool?) ?? false,
      delivered: (data['delivered'] as bool?) ?? false,
      type: type,
      trackData: trackData,
      reactions: reactions,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'senderId': senderId,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
      'read': read,
      'delivered': delivered,
      'type': type == MessageType.track ? 'track' : 'text',
    };

    if (trackData != null) {
      map['trackData'] = trackData!.toMap();
    }

    if (reactions.isNotEmpty) {
      map['reactions'] = reactions;
    }

    return map;
  }

  Message copyWith({bool? read, bool? delivered}) {
    return Message(
      id: id,
      senderId: senderId,
      text: text,
      timestamp: timestamp,
      read: read ?? this.read,
      delivered: delivered ?? this.delivered,
      isPending: isPending,
      type: type,
      trackData: trackData,
      reactions: reactions,
    );
  }
}
