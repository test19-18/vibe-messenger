import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/features/profile/domain/user_profile.dart';

void main() {
  test('maps presence from the user_presence relation', () {
    final profile = UserProfile.fromMap({
      'id': 'user-id',
      'display_name': 'Вера',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'user_presence': {
        'last_seen_at': '2099-01-01T00:00:00Z',
        'online_until': '2099-01-01T00:05:00Z',
      },
    });

    expect(profile.lastSeenAt, isNotNull);
    expect(profile.onlineUntil, isNotNull);
    expect(profile.isOnline, isTrue);
  });

  test('profile update map follows column-level grants', () {
    final profile = UserProfile(
      id: 'user-id',
      displayName: 'Вера',
      username: 'vera.vibe',
      avatarPath: 'user-id/avatar.webp',
      bio: 'На связи',
      createdAt: DateTime.utc(2026),
    );

    final update = profile.toUpdateMap();

    expect(update, isNot(contains('id')));
    expect(update['avatar_path'], 'user-id/avatar.webp');
    expect(update, isNot(contains('avatar_url')));
    expect(profile.toInsertMap()['id'], 'user-id');
  });
}
