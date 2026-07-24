import 'chat_message.dart';

enum ScheduledMessageStatus { pending, cancelled, delivered, failed }

class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    required this.body,
    required this.metadata,
    required this.scheduledFor,
    required this.silent,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.replyToId,
    this.deliveredMessageId,
    this.cancelledAt,
    this.deliveredAt,
    this.failedAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageKind kind;
  final String body;
  final Map<String, dynamic> metadata;
  final String? replyToId;
  final DateTime scheduledFor;
  final bool silent;
  final ScheduledMessageStatus status;
  final String? deliveredMessageId;
  final DateTime? cancelledAt;
  final DateTime? deliveredAt;
  final DateTime? failedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get canCancel => status == ScheduledMessageStatus.pending;

  factory ScheduledMessage.fromMap(Map<String, dynamic> map) {
    final createdAt =
        _date(map['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    return ScheduledMessage(
      id: _requiredString(map['id']),
      conversationId: _requiredString(map['conversation_id']),
      senderId: _requiredString(map['sender_id']),
      kind: _kind(map['kind']),
      body: _string(map['body']) ?? '',
      metadata: _map(map['metadata']) ?? const {},
      replyToId: _string(map['reply_to']),
      scheduledFor: _requiredDate(map['scheduled_for']),
      silent: map['silent'] as bool? ?? false,
      status: _status(map['status']),
      deliveredMessageId: _string(map['delivered_message_id']),
      cancelledAt: _date(map['cancelled_at']),
      deliveredAt: _date(map['delivered_at']),
      failedAt: _date(map['failed_at']),
      createdAt: createdAt,
      updatedAt: _date(map['updated_at']) ?? createdAt,
    );
  }
}

ScheduledMessageStatus _status(Object? value) {
  return ScheduledMessageStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ScheduledMessageStatus.pending,
  );
}

MessageKind _kind(Object? value) {
  return MessageKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => MessageKind.text,
  );
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final result = _string(value);
  if (result == null || result.isEmpty) {
    throw const FormatException('Некорректные данные отложенного сообщения.');
  }
  return result;
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

DateTime _requiredDate(Object? value) {
  final result = _date(value);
  if (result == null) {
    throw const FormatException('Некорректная дата отложенного сообщения.');
  }
  return result;
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
