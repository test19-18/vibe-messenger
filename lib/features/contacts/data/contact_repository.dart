import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/contact_relationship.dart';

class ContactRepository {
  const ContactRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  Future<List<ContactRelationship>> listRelationships(String userId) async {
    final rows = await _requiredClient
        .from('contacts')
        .select()
        .or('requester_id.eq.$userId,addressee_id.eq.$userId')
        .order('updated_at', ascending: false);
    final relationships = rows.map(ContactRelationship.fromMap).toList();
    if (relationships.isEmpty) {
      return relationships;
    }
    final ids = relationships
        .map((relationship) => relationship.otherUserId(userId))
        .toSet()
        .toList();
    final profileRows = await _requiredClient
        .from('profiles')
        .select(
          'id,username,display_name,avatar_path,bio,created_at,updated_at,'
          'user_presence(last_seen_at,online_until)',
        )
        .inFilter('id', ids);
    final profiles = <String, UserProfile>{};
    for (final row in profileRows) {
      final profile = UserProfile.fromMap(row);
      profiles[profile.id] = await _withAvatar(profile);
    }
    return relationships
        .map(
          (relationship) => relationship.copyWith(
            profile: profiles[relationship.otherUserId(userId)],
          ),
        )
        .toList();
  }

  Future<List<BlockedUser>> listBlockedUsers(String userId) async {
    final rows = await _requiredClient
        .from('user_blocks')
        .select('blocked_id,created_at')
        .eq('blocker_id', userId)
        .order('created_at', ascending: false);
    return rows.map(BlockedUser.fromMap).toList();
  }

  Future<void> sendRequest({
    required String requesterId,
    required String addresseeId,
  }) async {
    await _requiredClient.from('contacts').insert({
      'requester_id': requesterId,
      'addressee_id': addresseeId,
    });
  }

  Future<void> updateStatus(String relationshipId, ContactStatus status) async {
    await _requiredClient
        .from('contacts')
        .update({'status': status.name})
        .eq('id', relationshipId);
  }

  Future<void> removeContact(String relationshipId) async {
    await _requiredClient.from('contacts').delete().eq('id', relationshipId);
  }

  Future<void> block({
    required String blockerId,
    required String blockedId,
  }) async {
    await _requiredClient.from('user_blocks').insert({
      'blocker_id': blockerId,
      'blocked_id': blockedId,
    });
  }

  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) async {
    await _requiredClient
        .from('user_blocks')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId);
  }

  Future<void> reportUser({
    required String reporterId,
    required String userId,
    required String reason,
    String? details,
  }) async {
    await _requiredClient.from('reports').insert({
      'reporter_id': reporterId,
      'reported_user_id': userId,
      'reason': reason.trim(),
      'details': _nullable(details),
    });
  }

  Future<void> reportConversation({
    required String reporterId,
    required String conversationId,
    required String reason,
    String? details,
  }) async {
    await _requiredClient.from('reports').insert({
      'reporter_id': reporterId,
      'reported_conversation_id': conversationId,
      'reason': reason.trim(),
      'details': _nullable(details),
    });
  }

  Future<void> reportMessage({
    required String reporterId,
    required String messageId,
    required String reason,
    String? details,
  }) async {
    await _requiredClient.from('reports').insert({
      'reporter_id': reporterId,
      'reported_message_id': messageId,
      'reason': reason.trim(),
      'details': _nullable(details),
    });
  }

  Future<UserProfile> _withAvatar(UserProfile profile) async {
    final path = profile.avatarPath?.trim();
    if (path == null || path.isEmpty) {
      return profile;
    }
    try {
      final url = await _requiredClient.storage
          .from('avatars')
          .createSignedUrl(path, 3600);
      return profile.copyWith(avatarUrl: url);
    } catch (_) {
      return profile;
    }
  }
}

String? _nullable(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
