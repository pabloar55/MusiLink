import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo que representa una conversación individual o grupal.
class Chat {
  final String id;
  final bool isGroup;
  final String name;

  /// Foto del grupo en Storage; vacía si no tiene o en chats individuales.
  final String photoUrl;
  final String? createdBy;
  final List<String> participants;
  final String lastMessage;
  final DateTime lastMessageTime;
  final DateTime createdAt;

  /// Mensajes no leídos por UID. Clave = UID del destinatario, valor = contador.
  /// Se mantiene desnormalizado en el documento del chat para evitar listeners
  /// por chat en la lista de conversaciones.
  final Map<String, int> unreadCounts;

  /// Timestamp de borrado suave por UID. Si deletedAt[uid] != null y
  /// lastMessageTime <= deletedAt[uid], el chat está oculto para ese usuario.
  final Map<String, DateTime> deletedAt;

  const Chat({
    required this.id,
    this.isGroup = false,
    this.name = '',
    this.photoUrl = '',
    this.createdBy,
    required this.participants,
    this.lastMessage = '',
    required this.lastMessageTime,
    required this.createdAt,
    this.unreadCounts = const {},
    this.deletedAt = const {},
  });

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    final rawCounts = data['unreadCounts'] as Map<String, dynamic>? ?? {};
    final rawDeletedAt = data['deletedAt'] as Map<String, dynamic>? ?? {};
    return Chat(
      id: doc.id,
      isGroup: data['type'] == 'group',
      name: (data['name'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      createdBy: data['createdBy'] as String?,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: (data['lastMessage'] ?? '').toString(),
      lastMessageTime:
          (data['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      unreadCounts: rawCounts.map((k, v) => MapEntry(k, (v as num).toInt())),
      deletedAt: {
        for (final e in rawDeletedAt.entries)
          if (e.value is Timestamp) e.key: (e.value as Timestamp).toDate(),
      },
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (isGroup) ...{'type': 'group', 'name': name, 'createdBy': createdBy},
      if (photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'createdAt': Timestamp.fromDate(createdAt),
      'unreadCounts': unreadCounts,
      'deletedAt': deletedAt.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
    };
  }

  Chat copyWith({String? lastMessage, DateTime? lastMessageTime}) {
    return Chat(
      id: id,
      isGroup: isGroup,
      name: name,
      photoUrl: photoUrl,
      createdBy: createdBy,
      participants: participants,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      createdAt: createdAt,
      unreadCounts: unreadCounts,
      deletedAt: deletedAt,
    );
  }
}
