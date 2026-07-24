class UserDevice {
  const UserDevice({
    required this.id,
    required this.userId,
    required this.platform,
    required this.lastSeenAt,
    required this.createdAt,
    this.deviceName,
    this.appVersion,
    this.disabledAt,
  });

  final String id;
  final String userId;
  final String platform;
  final String? deviceName;
  final String? appVersion;
  final DateTime lastSeenAt;
  final DateTime createdAt;
  final DateTime? disabledAt;

  bool get isActive => disabledAt == null;

  factory UserDevice.fromMap(Map<String, dynamic> map) {
    return UserDevice(
      id: _required(map['id']),
      userId: _required(map['user_id']),
      platform: _required(map['platform']),
      deviceName: map['device_name'] as String?,
      appVersion: map['app_version'] as String?,
      lastSeenAt:
          _date(map['last_seen_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt:
          _date(map['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      disabledAt: _date(map['disabled_at']),
    );
  }
}

String _required(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Некорректные данные устройства.');
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
