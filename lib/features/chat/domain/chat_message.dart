enum MessageKind {
  text,
  image,
  video,
  file,
  audio,
  voice,
  location,
  contact,
  poll,
  system,
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    required this.body,
    required this.metadata,
    required this.createdAt,
    this.replyToId,
    this.clientNonce,
    this.editedAt,
    this.deletedAt,
    this.deletedBy,
    this.expiresAt,
  });

  final String id;
  final String conversationId;
  final String? senderId;
  final MessageKind kind;
  final String body;
  final Map<String, dynamic> metadata;
  final String? replyToId;
  final String? clientNonce;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? deletedBy;
  final DateTime? expiresAt;

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null && deletedAt == null;
  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now());
  }

  bool get isVisible => !isExpired;

  String get visibleBody {
    if (isDeleted) {
      return 'Сообщение удалено';
    }
    final normalized = body.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return switch (kind) {
      MessageKind.image => 'Изображение',
      MessageKind.video => 'Видео',
      MessageKind.file => 'Документ',
      MessageKind.audio => 'Аудио',
      MessageKind.voice => 'Голосовое сообщение',
      MessageKind.location => 'Геопозиция',
      MessageKind.contact => 'Контакт',
      MessageKind.poll => 'Опрос',
      MessageKind.system => 'Системное сообщение',
      MessageKind.text => '',
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: _requiredString(map['id']),
      conversationId: _requiredString(map['conversation_id']),
      senderId: _string(map['sender_id']),
      kind: _kind(map['kind']),
      body: _string(map['body']) ?? '',
      metadata: _map(map['metadata']) ?? const {},
      replyToId: _string(map['reply_to_message_id']),
      clientNonce: _string(map['client_nonce']),
      createdAt:
          _date(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal(),
      editedAt: _date(map['edited_at']),
      deletedAt: _date(map['deleted_at']),
      deletedBy: _string(map['deleted_by']),
      expiresAt: _date(map['expires_at']),
    );
  }
}

MessageKind _kind(Object? value) {
  return MessageKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => MessageKind.text,
  );
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final string = _string(value);
  if (string == null || string.isEmpty) {
    throw const FormatException('Некорректные данные сообщения.');
  }
  return string;
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value.toLocal();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}
