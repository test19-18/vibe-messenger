import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/chat/domain/chat_message.dart';
import 'package:vibe_messenger/features/chat/domain/scheduled_message.dart';

void main() {
  test('maps scheduled message status, timing and silent flag', () {
    final scheduled = ScheduledMessage.fromMap({
      'id': 'scheduled-id',
      'conversation_id': 'conversation-id',
      'sender_id': 'sender-id',
      'kind': 'text',
      'body': 'Напомнить команде',
      'metadata': {'source': 'test'},
      'reply_to': 'reply-id',
      'scheduled_for': '2026-08-01T09:30:00Z',
      'silent': true,
      'status': 'pending',
      'created_at': '2026-07-24T10:00:00Z',
      'updated_at': '2026-07-24T10:01:00Z',
    });

    expect(scheduled.kind, MessageKind.text);
    expect(scheduled.status, ScheduledMessageStatus.pending);
    expect(
      scheduled.scheduledFor,
      DateTime.parse('2026-08-01T09:30:00Z').toLocal(),
    );
    expect(scheduled.silent, isTrue);
    expect(scheduled.replyToId, 'reply-id');
    expect(scheduled.canCancel, isTrue);
  });

  test('delivered scheduled message cannot be cancelled', () {
    final scheduled = ScheduledMessage.fromMap({
      'id': 'scheduled-id',
      'conversation_id': 'conversation-id',
      'sender_id': 'sender-id',
      'kind': 'location',
      'body': 'Точка встречи',
      'metadata': const <String, dynamic>{},
      'scheduled_for': '2026-08-01T09:30:00Z',
      'silent': false,
      'status': 'delivered',
      'delivered_message_id': 'message-id',
      'delivered_at': '2026-08-01T09:30:01Z',
      'created_at': '2026-07-24T10:00:00Z',
      'updated_at': '2026-08-01T09:30:01Z',
    });

    expect(scheduled.status, ScheduledMessageStatus.delivered);
    expect(scheduled.deliveredMessageId, 'message-id');
    expect(scheduled.canCancel, isFalse);
  });
}
