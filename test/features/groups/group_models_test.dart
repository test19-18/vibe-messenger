import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/groups/domain/group_models.dart';

void main() {
  test('accepts groups and explicitly rejects channel UI data', () {
    final group = GroupDetails.fromMap({
      'id': 'group-id',
      'kind': 'group',
      'title': 'Команда',
      'is_locked': true,
      'join_requests_enabled': true,
      'created_at': '2026-07-01T10:00:00Z',
    });

    expect(group.title, 'Команда');
    expect(group.isLocked, isTrue);
    expect(group.joinRequestsEnabled, isTrue);

    expect(
      () => GroupDetails.fromMap({
        'id': 'channel-id',
        'kind': 'channel',
        'title': 'Канал',
      }),
      throwsFormatException,
    );
  });

  test('maps a server-backed personal member tag', () {
    final tag = ConversationMemberTag.fromMap({
      'conversation_id': 'group-id',
      'user_id': 'owner-id',
      'member_id': 'member-id',
      'tag': 'Дизайнер',
      'created_at': '2026-07-24T10:00:00Z',
      'updated_at': '2026-07-24T11:00:00Z',
    });

    expect(tag.memberId, 'member-id');
    expect(tag.tag, 'Дизайнер');
  });
}
