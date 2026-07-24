import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/chat/domain/chat_message.dart';
import 'package:vibe_messenger/features/chat/domain/message_details.dart';

void main() {
  test('maps media attachment metadata', () {
    final attachment = MessageAttachment.fromMap({
      'id': 'attachment-id',
      'message_id': 'message-id',
      'conversation_id': 'conversation-id',
      'kind': 'voice',
      'storage_bucket': 'voice-messages',
      'storage_path': 'conversation/user/voice.m4a',
      'file_name': 'voice.m4a',
      'mime_type': 'audio/mp4',
      'byte_size': 1024,
      'duration_ms': 4200,
      'created_at': '2026-07-01T10:00:00Z',
    });

    expect(attachment.kind, MessageKind.voice);
    expect(attachment.durationMs, 4200);
    expect(attachment.storageBucket, 'voice-messages');
  });

  test('maps RPC poll results and selected state', () {
    final option = PollOption.fromMap({
      'option_id': 'option-id',
      'option_text': 'Да',
      'option_position': 0,
      'vote_count': 3,
      'selected_by_me': true,
    });

    expect(option.position, 0);
    expect(option.voteCount, 3);
    expect(option.selectedByMe, isTrue);
  });
}
