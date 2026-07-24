import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../domain/group_models.dart';

class GroupRepository {
  const GroupRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  Future<GroupDetails> getGroup(String conversationId) async {
    final row = await _requiredClient
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .eq('kind', 'group')
        .single();
    String? avatarUrl;
    final path = row['avatar_path'] as String?;
    if (path != null) {
      try {
        avatarUrl = await _requiredClient.storage
            .from('avatars')
            .createSignedUrl(path, 3600);
      } catch (_) {
        avatarUrl = null;
      }
    }
    return GroupDetails.fromMap(row, avatarUrl: avatarUrl);
  }

  Future<List<GroupMember>> listMembers(String conversationId) async {
    final rows = await _requiredClient
        .from('conversation_members')
        .select(
          'conversation_id,user_id,role,status,joined_at,'
          'profiles!conversation_members_user_id_fkey('
          'id,username,display_name,avatar_path,bio,created_at,updated_at,'
          'user_presence(last_seen_at,online_until))',
        )
        .eq('conversation_id', conversationId)
        .order('joined_at');
    final tags = await listMemberTags(conversationId);
    final tagsByMember = {for (final tag in tags) tag.memberId: tag.tag};
    return rows
        .map(
          (row) => GroupMember.fromMap(
            row,
            tag: tagsByMember[row['user_id'] as String],
          ),
        )
        .toList();
  }

  Future<void> updateGroup({
    required String conversationId,
    required String title,
    String? description,
    String? avatarPath,
    required bool isLocked,
    required bool joinRequestsEnabled,
  }) async {
    await _requiredClient
        .from('conversations')
        .update({
          'title': title.trim(),
          'description': _nullable(description),
          'avatar_path': _nullable(avatarPath),
          'is_locked': isLocked,
          'join_requests_enabled': joinRequestsEnabled,
        })
        .eq('id', conversationId)
        .eq('kind', 'group');
  }

  Future<String> uploadGroupAvatar({
    required String conversationId,
    required String userId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Аватар должен быть меньше 10 МБ.');
    }
    final safeExtension = extension.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    final path =
        '$conversationId/$userId/group-'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}.'
        '${safeExtension.isEmpty ? 'jpg' : safeExtension}';
    await _requiredClient.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<void> updateMember({
    required String conversationId,
    required String userId,
    String? role,
    String? status,
  }) async {
    final values = <String, dynamic>{};
    if (role != null) {
      values['role'] = role;
    }
    if (status != null) {
      values['status'] = status;
    }
    if (values.isEmpty) {
      return;
    }
    await _requiredClient
        .from('conversation_members')
        .update(values)
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  Future<void> transferOwnership({
    required String conversationId,
    required String newOwnerId,
  }) async {
    await _requiredClient.rpc(
      'transfer_conversation_ownership',
      params: {'_conversation_id': conversationId, '_new_owner_id': newOwnerId},
    );
  }

  Future<void> inviteUser({
    required String conversationId,
    required String inviterId,
    required String inviteeId,
  }) async {
    await _requiredClient.from('group_invitations').insert({
      'conversation_id': conversationId,
      'inviter_id': inviterId,
      'invitee_id': inviteeId,
    });
  }

  Future<List<GroupInvitation>> listUserInvitations(String userId) async {
    final rows = await _requiredClient
        .from('group_invitations')
        .select()
        .eq('invitee_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return rows.map(GroupInvitation.fromMap).toList();
  }

  Future<List<GroupInvitation>> listInvitations(String conversationId) async {
    final rows = await _requiredClient
        .from('group_invitations')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false);
    return rows.map(GroupInvitation.fromMap).toList();
  }

  Future<void> updateInvitation(String id, String status) async {
    await _requiredClient
        .from('group_invitations')
        .update({'status': status})
        .eq('id', id);
  }

  Future<String> acceptInvitation(String id) async {
    final invite = await _requiredClient
        .from('group_invitations')
        .select('conversation_id')
        .eq('id', id)
        .single();
    await _ensureGroup(invite['conversation_id'] as String);
    final response = await _requiredClient.rpc(
      'accept_group_invitation',
      params: {'_invitation_id': id},
    );
    if (response is! String) {
      throw const FormatException('Backend не вернул идентификатор группы.');
    }
    return response;
  }

  Future<GroupInviteLink> createInviteLink({
    required String conversationId,
    required DateTime? expiresAt,
    required int maxUses,
  }) async {
    final response = await _requiredClient.rpc(
      'create_group_invite_link',
      params: {
        '_conversation_id': conversationId,
        '_expires_at': expiresAt?.toUtc().toIso8601String(),
        '_max_uses': maxUses,
      },
    );
    final row = response is List && response.isNotEmpty ? response.first : null;
    if (row is! Map) {
      throw const FormatException('Backend не вернул ссылку-приглашение.');
    }
    return GroupInviteLink(
      invitationId: row['invitation_id'] as String,
      token: row['token'] as String,
    );
  }

  Future<String> acceptInviteToken(String token) async {
    final response = await _requiredClient.rpc(
      'accept_group_invite_token',
      params: {'_token': token.trim()},
    );
    if (response is! String) {
      throw const FormatException('Ссылка-приглашение недействительна.');
    }
    try {
      await _ensureGroup(response);
    } on FormatException {
      final userId = _requiredClient.auth.currentUser?.id;
      if (userId != null) {
        try {
          await _requiredClient
              .from('conversation_members')
              .update({'status': 'left'})
              .eq('conversation_id', response)
              .eq('user_id', userId);
        } catch (_) {
          // Server-side channel invite handling is outside this client's scope.
        }
      }
      rethrow;
    }
    return response;
  }

  Future<List<GroupJoinRequest>> listJoinRequests(String conversationId) async {
    final rows = await _requiredClient
        .from('group_join_requests')
        .select(
          'id,conversation_id,requester_id,message,status,created_at,'
          'profiles!group_join_requests_requester_id_fkey('
          'id,username,display_name,avatar_path,bio,created_at,updated_at)',
        )
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows.map(GroupJoinRequest.fromMap).toList();
  }

  Future<void> createJoinRequest({
    required String conversationId,
    required String requesterId,
    String? message,
  }) async {
    await _requiredClient.from('group_join_requests').insert({
      'conversation_id': conversationId,
      'requester_id': requesterId,
      'message': _nullable(message),
    });
  }

  Future<void> reviewJoinRequest(
    String requestId, {
    required bool approve,
  }) async {
    await _requiredClient.rpc(
      'review_group_join_request',
      params: {'_request_id': requestId, '_approve': approve},
    );
  }

  Future<void> _ensureGroup(String conversationId) async {
    final row = await _requiredClient
        .from('conversations')
        .select('kind')
        .eq('id', conversationId)
        .single();
    if (row['kind'] != 'group') {
      throw const FormatException('Channel invitations are not supported.');
    }
  }

  Future<List<ConversationMemberTag>> listMemberTags(
    String conversationId,
  ) async {
    final rows = await _requiredClient
        .from('conversation_member_tags')
        .select()
        .eq('conversation_id', conversationId)
        .order('updated_at', ascending: false);
    return rows.map(ConversationMemberTag.fromMap).toList();
  }

  Future<void> saveMemberTag({
    required String conversationId,
    required String memberId,
    required String? tag,
  }) async {
    final userId = _requiredClient.auth.currentUser?.id;
    if (userId == null) {
      throw const BackendUnavailableException('Сессия не найдена.');
    }
    final normalized = _nullable(tag);
    if (normalized == null) {
      await _requiredClient
          .from('conversation_member_tags')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', userId)
          .eq('member_id', memberId);
      return;
    }
    if (normalized.length > 64) {
      throw const FormatException('Метка должна быть короче 65 символов.');
    }
    final updated = await _requiredClient
        .from('conversation_member_tags')
        .update({'tag': normalized})
        .eq('conversation_id', conversationId)
        .eq('user_id', userId)
        .eq('member_id', memberId)
        .select('member_id')
        .maybeSingle();
    if (updated == null) {
      await _requiredClient.from('conversation_member_tags').insert({
        'conversation_id': conversationId,
        'user_id': userId,
        'member_id': memberId,
        'tag': normalized,
      });
    }
  }
}

String? _nullable(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
