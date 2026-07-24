import '../../profile/domain/user_profile.dart';

enum ContactStatus { pending, accepted, declined, cancelled }

class ContactRelationship {
  const ContactRelationship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
    this.respondedAt,
    this.profile,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final ContactStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final UserProfile? profile;

  bool isIncomingFor(String userId) => addresseeId == userId;
  String otherUserId(String userId) =>
      requesterId == userId ? addresseeId : requesterId;

  factory ContactRelationship.fromMap(
    Map<String, dynamic> map, {
    UserProfile? profile,
  }) {
    return ContactRelationship(
      id: _requiredString(map['id']),
      requesterId: _requiredString(map['requester_id']),
      addresseeId: _requiredString(map['addressee_id']),
      status: _status(map['status']),
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      respondedAt: _date(map['responded_at']),
      profile: profile,
    );
  }

  ContactRelationship copyWith({UserProfile? profile}) {
    return ContactRelationship(
      id: id,
      requesterId: requesterId,
      addresseeId: addresseeId,
      status: status,
      createdAt: createdAt,
      respondedAt: respondedAt,
      profile: profile ?? this.profile,
    );
  }
}

class BlockedUser {
  const BlockedUser({required this.userId, required this.createdAt});

  final String userId;
  final DateTime createdAt;

  factory BlockedUser.fromMap(Map<String, dynamic> map) {
    return BlockedUser(
      userId: _requiredString(map['blocked_id']),
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

ContactStatus _status(Object? value) {
  return switch (value) {
    'accepted' => ContactStatus.accepted,
    'declined' => ContactStatus.declined,
    'cancelled' => ContactStatus.cancelled,
    _ => ContactStatus.pending,
  };
}

String _requiredString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Некорректные данные контакта.');
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
