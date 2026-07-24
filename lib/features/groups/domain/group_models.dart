import '../../profile/domain/user_profile.dart';

class GroupDetails {
  const GroupDetails({
    required this.id,
    required this.title,
    required this.isLocked,
    required this.joinRequestsEnabled,
    required this.createdAt,
    this.description,
    this.avatarPath,
    this.avatarUrl,
  });

  final String id;
  final String title;
  final String? description;
  final String? avatarPath;
  final String? avatarUrl;
  final bool isLocked;
  final bool joinRequestsEnabled;
  final DateTime createdAt;

  factory GroupDetails.fromMap(Map<String, dynamic> map, {String? avatarUrl}) {
    if (map['kind'] != 'group') {
      throw const FormatException('Каналы не поддерживаются клиентом.');
    }
    return GroupDetails(
      id: _required(map['id']),
      title: _required(map['title']),
      description: map['description'] as String?,
      avatarPath: map['avatar_path'] as String?,
      avatarUrl: avatarUrl,
      isLocked: map['is_locked'] as bool? ?? false,
      joinRequestsEnabled: map['join_requests_enabled'] as bool? ?? false,
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.profile,
    this.localTag,
  });

  final String conversationId;
  final String userId;
  final String role;
  final String status;
  final DateTime joinedAt;
  final UserProfile? profile;
  final String? localTag;

  bool get isActive => status == 'active';
  bool get isAdmin => role == 'owner' || role == 'admin';

  factory GroupMember.fromMap(Map<String, dynamic> map, {String? localTag}) {
    final profileMap = map['profiles'];
    return GroupMember(
      conversationId: _required(map['conversation_id']),
      userId: _required(map['user_id']),
      role: _required(map['role']),
      status: _required(map['status']),
      joinedAt:
          _date(map['joined_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      profile: profileMap is Map
          ? UserProfile.fromMap(Map<String, dynamic>.from(profileMap))
          : null,
      localTag: localTag,
    );
  }
}

class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.conversationId,
    required this.status,
    required this.maxUses,
    required this.useCount,
    required this.createdAt,
    this.inviteeId,
    this.expiresAt,
  });

  final String id;
  final String conversationId;
  final String? inviteeId;
  final String status;
  final int maxUses;
  final int useCount;
  final DateTime? expiresAt;
  final DateTime createdAt;

  factory GroupInvitation.fromMap(Map<String, dynamic> map) {
    return GroupInvitation(
      id: _required(map['id']),
      conversationId: _required(map['conversation_id']),
      inviteeId: map['invitee_id'] as String?,
      status: _required(map['status']),
      maxUses: (map['max_uses'] as num?)?.toInt() ?? 1,
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      expiresAt: _date(map['expires_at']),
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class GroupJoinRequest {
  const GroupJoinRequest({
    required this.id,
    required this.conversationId,
    required this.requesterId,
    required this.status,
    required this.createdAt,
    this.message,
    this.profile,
  });

  final String id;
  final String conversationId;
  final String requesterId;
  final String status;
  final String? message;
  final DateTime createdAt;
  final UserProfile? profile;

  factory GroupJoinRequest.fromMap(Map<String, dynamic> map) {
    final profileMap = map['profiles'];
    return GroupJoinRequest(
      id: _required(map['id']),
      conversationId: _required(map['conversation_id']),
      requesterId: _required(map['requester_id']),
      status: _required(map['status']),
      message: map['message'] as String?,
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      profile: profileMap is Map
          ? UserProfile.fromMap(Map<String, dynamic>.from(profileMap))
          : null,
    );
  }
}

class GroupInviteLink {
  const GroupInviteLink({required this.invitationId, required this.token});

  final String invitationId;
  final String token;

  String get uri => 'vibe://group-invite/$token';
}

String _required(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Некорректные данные группы.');
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
