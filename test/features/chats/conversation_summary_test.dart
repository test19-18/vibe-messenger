import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/chats/domain/conversation_summary.dart';

void main() {
  test('maps per-user chat organization settings', () {
    final summary = ConversationSummary.fromMap(
      {
        'id': 'conversation-id',
        'kind': 'group',
        'title': 'Команда',
        'created_at': '2026-07-01T10:00:00Z',
        'updated_at': '2026-07-01T11:00:00Z',
      },
      unreadCount: 4,
      userSettings: {
        'is_archived': true,
        'is_pinned': true,
        'notification_level': 'mentions',
        'custom_title': 'Работа',
        'draft': 'Набросок',
        'auto_delete_seconds': 86400,
        'protected_content': true,
      },
      folderIds: {'folder-id'},
    );

    expect(summary.visibleTitle, 'Работа');
    expect(summary.isArchived, isTrue);
    expect(summary.isPinned, isTrue);
    expect(summary.draft, 'Набросок');
    expect(summary.autoDeleteSeconds, 86400);
    expect(summary.protectedContent, isTrue);
    expect(summary.folderIds, contains('folder-id'));
  });
}
