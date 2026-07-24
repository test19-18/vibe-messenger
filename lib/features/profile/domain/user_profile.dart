import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.createdAt,
    this.username,
    this.displayName,
    this.avatarPath,
    this.avatarUrl,
    this.bio,
    this.lastSeenAt,
    this.onlineUntil,
    this.updatedAt,
  });

  final String id;
  final String? username;
  final String? displayName;
  final String? avatarPath;
  final String? avatarUrl;
  final String? bio;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final DateTime? onlineUntil;
  final DateTime? updatedAt;

  String get visibleName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) {
      return '@$handle';
    }
    return 'Пользователь Вайба';
  }

  String get handle {
    final value = username?.trim();
    return value == null || value.isEmpty ? '' : '@$value';
  }

  bool get isOnline {
    final now = DateTime.now();
    final until = onlineUntil;
    if (until != null) {
      return until.isAfter(now);
    }
    final seenAt = lastSeenAt;
    return seenAt != null && now.difference(seenAt).inMinutes < 3;
  }

  factory UserProfile.fromMap(
    Map<String, dynamic> map, {
    DateTime? lastSeenAt,
    DateTime? onlineUntil,
  }) {
    final presence = _map(map['user_presence']);
    return UserProfile(
      id: _requiredString(map['id']),
      username: _string(map['username']),
      displayName: _string(map['display_name']),
      avatarPath: _string(map['avatar_path']),
      avatarUrl: _string(map['avatar_url']),
      bio: _string(map['bio']),
      createdAt:
          _date(map['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal(),
      lastSeenAt: lastSeenAt ?? _date(presence?['last_seen_at']),
      onlineUntil: onlineUntil ?? _date(presence?['online_until']),
      updatedAt: _date(map['updated_at']),
    );
  }

  factory UserProfile.fromAuthUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return UserProfile(
      id: user.id,
      username: _string(metadata['username']),
      displayName: _string(
        metadata['full_name'] ?? metadata['name'] ?? metadata['display_name'],
      ),
      avatarPath: _string(metadata['avatar_path']),
      avatarUrl: _string(metadata['avatar_url']),
      createdAt: DateTime.tryParse(user.createdAt) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'username': _nullableTrim(username),
      'display_name': displayName?.trim(),
      'avatar_path': _nullableTrim(avatarPath),
      'bio': _nullableTrim(bio),
    };
  }

  Map<String, dynamic> toInsertMap() => {'id': id, ...toUpdateMap()};

  UserProfile copyWith({
    String? username,
    String? displayName,
    String? avatarPath,
    String? avatarUrl,
    String? bio,
  }) {
    return UserProfile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      createdAt: createdAt,
      lastSeenAt: lastSeenAt,
      onlineUntil: onlineUntil,
      updatedAt: updatedAt,
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final string = _string(value);
  if (string == null || string.isEmpty) {
    throw const FormatException('Некорректные данные профиля.');
  }
  return string;
}

String? _nullableTrim(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
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
