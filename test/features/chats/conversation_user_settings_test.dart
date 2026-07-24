import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/chats/domain/conversation_user_settings.dart';

void main() {
  test('maps auto-delete and protected-content extensions', () {
    final settings = ConversationUserSettings.fromMap({
      'conversation_id': 'conversation-id',
      'user_id': 'user-id',
      'is_archived': false,
      'is_pinned': true,
      'notification_level': 'mentions',
      'auto_delete_seconds': 86400,
      'protected_content': true,
      'created_at': '2026-07-24T10:00:00Z',
      'updated_at': '2026-07-24T11:00:00Z',
    });

    expect(settings.autoDeleteEnabled, isTrue);
    expect(settings.autoDeleteDuration, const Duration(days: 1));
    expect(settings.protectedContent, isTrue);
    expect(settings.isPinned, isTrue);
  });

  test('defaults extensions safely and rejects an invalid timer', () {
    final settings = ConversationUserSettings.defaults(
      conversationId: 'conversation-id',
      userId: 'user-id',
    );

    expect(settings.autoDeleteSeconds, isNull);
    expect(settings.autoDeleteEnabled, isFalse);
    expect(settings.protectedContent, isFalse);

    expect(
      () => ConversationUserSettings.fromMap({
        'conversation_id': 'conversation-id',
        'user_id': 'user-id',
        'auto_delete_seconds': 0,
      }),
      throwsFormatException,
    );
  });
}
