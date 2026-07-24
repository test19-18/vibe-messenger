import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/chat/domain/chat_message.dart';

void main() {
  test('maps the backend message contract including reply and edit state', () {
    final message = ChatMessage.fromMap({
      'id': 'message-id',
      'conversation_id': 'conversation-id',
      'sender_id': null,
      'body': 'Привет',
      'reply_to_message_id': 'parent-id',
      'created_at': '2026-01-02T10:00:00Z',
      'edited_at': '2026-01-02T10:01:00Z',
      'deleted_at': null,
      'expires_at': '2026-01-03T10:00:00Z',
    });

    expect(message.senderId, isNull);
    expect(message.replyToId, 'parent-id');
    expect(message.isEdited, isTrue);
    expect(message.visibleBody, 'Привет');
    expect(message.expiresAt, DateTime.parse('2026-01-03T10:00:00Z').toLocal());
  });
}
