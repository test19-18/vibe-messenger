import 'chat_message.dart';

class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.kind,
    required this.storageBucket,
    required this.storagePath,
    required this.createdAt,
    this.fileName,
    this.mimeType,
    this.byteSize,
    this.width,
    this.height,
    this.durationMs,
    this.signedUrl,
  });

  final String id;
  final String messageId;
  final String conversationId;
  final MessageKind kind;
  final String storageBucket;
  final String storagePath;
  final DateTime createdAt;
  final String? fileName;
  final String? mimeType;
  final int? byteSize;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? signedUrl;

  factory MessageAttachment.fromMap(
    Map<String, dynamic> map, {
    String? signedUrl,
  }) {
    return MessageAttachment(
      id: _requiredString(map['id']),
      messageId: _requiredString(map['message_id']),
      conversationId: _requiredString(map['conversation_id']),
      kind: _messageKind(map['kind']),
      storageBucket: _requiredString(map['storage_bucket']),
      storagePath: _requiredString(map['storage_path']),
      fileName: _string(map['file_name']),
      mimeType: _string(map['mime_type']),
      byteSize: _integer(map['byte_size']),
      width: _integer(map['width']),
      height: _integer(map['height']),
      durationMs: _integer(map['duration_ms']),
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      signedUrl: signedUrl,
    );
  }

  MessageAttachment copyWith({String? signedUrl}) {
    return MessageAttachment(
      id: id,
      messageId: messageId,
      conversationId: conversationId,
      kind: kind,
      storageBucket: storageBucket,
      storagePath: storagePath,
      fileName: fileName,
      mimeType: mimeType,
      byteSize: byteSize,
      width: width,
      height: height,
      durationMs: durationMs,
      createdAt: createdAt,
      signedUrl: signedUrl ?? this.signedUrl,
    );
  }
}

class MessageReaction {
  const MessageReaction({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  factory MessageReaction.fromMap(Map<String, dynamic> map) {
    return MessageReaction(
      messageId: _requiredString(map['message_id']),
      userId: _requiredString(map['user_id']),
      emoji: _requiredString(map['emoji']),
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ConversationReadReceipt {
  const ConversationReadReceipt({
    required this.conversationId,
    required this.userId,
    required this.lastReadAt,
    this.lastReadMessageId,
  });

  final String conversationId;
  final String userId;
  final String? lastReadMessageId;
  final DateTime lastReadAt;

  factory ConversationReadReceipt.fromMap(Map<String, dynamic> map) {
    return ConversationReadReceipt(
      conversationId: _requiredString(map['conversation_id']),
      userId: _requiredString(map['user_id']),
      lastReadMessageId: _string(map['last_read_message_id']),
      lastReadAt:
          _date(map['last_read_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class PollDetails {
  const PollDetails({
    required this.id,
    required this.messageId,
    required this.question,
    required this.allowMultiple,
    required this.maxSelections,
    required this.isAnonymous,
    required this.options,
    this.closesAt,
    this.closedAt,
  });

  final String id;
  final String messageId;
  final String question;
  final bool allowMultiple;
  final int maxSelections;
  final bool isAnonymous;
  final DateTime? closesAt;
  final DateTime? closedAt;
  final List<PollOption> options;

  bool get isClosed =>
      closedAt != null ||
      (closesAt != null && !closesAt!.isAfter(DateTime.now()));

  factory PollDetails.fromMap(
    Map<String, dynamic> map, {
    List<PollOption> options = const [],
  }) {
    return PollDetails(
      id: _requiredString(map['id']),
      messageId: _requiredString(map['message_id']),
      question: _requiredString(map['question']),
      allowMultiple: map['allow_multiple'] as bool? ?? false,
      maxSelections: _integer(map['max_selections']) ?? 1,
      isAnonymous: map['is_anonymous'] as bool? ?? false,
      closesAt: _date(map['closes_at']),
      closedAt: _date(map['closed_at']),
      options: List.unmodifiable(options),
    );
  }
}

class PollOption {
  const PollOption({
    required this.id,
    required this.text,
    required this.position,
    required this.voteCount,
    required this.selectedByMe,
  });

  final String id;
  final String text;
  final int position;
  final int voteCount;
  final bool selectedByMe;

  factory PollOption.fromMap(Map<String, dynamic> map) {
    return PollOption(
      id: _requiredString(map['option_id'] ?? map['id']),
      text: _requiredString(map['option_text']),
      position: _integer(map['option_position'] ?? map['position']) ?? 0,
      voteCount: _integer(map['vote_count']) ?? 0,
      selectedByMe: map['selected_by_me'] as bool? ?? false,
    );
  }
}

MessageKind _messageKind(Object? value) {
  return MessageKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => MessageKind.file,
  );
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final text = _string(value);
  if (text == null || text.isEmpty) {
    throw const FormatException('Некорректные данные сообщения.');
  }
  return text;
}

int? _integer(Object? value) => value is num ? value.toInt() : null;

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value.toLocal();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}
