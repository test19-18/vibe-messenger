class ConversationUserSettings {
  const ConversationUserSettings({
    required this.conversationId,
    required this.userId,
    this.isArchived = false,
    this.isPinned = false,
    this.notificationLevel = 'all',
    this.protectedContent = false,
    this.muteUntil,
    this.customTitle,
    this.draft,
    this.autoDeleteSeconds,
    this.createdAt,
    this.updatedAt,
  });

  final String conversationId;
  final String userId;
  final bool isArchived;
  final bool isPinned;
  final DateTime? muteUntil;
  final String notificationLevel;
  final String? customTitle;
  final String? draft;
  final int? autoDeleteSeconds;
  final bool protectedContent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get autoDeleteEnabled => autoDeleteSeconds != null;

  Duration? get autoDeleteDuration {
    final seconds = autoDeleteSeconds;
    return seconds == null ? null : Duration(seconds: seconds);
  }

  factory ConversationUserSettings.fromMap(Map<String, dynamic> map) {
    final seconds = (map['auto_delete_seconds'] as num?)?.toInt();
    if (seconds != null && (seconds < 1 || seconds > 31536000)) {
      throw const FormatException('Некорректный таймер автоудаления.');
    }
    return ConversationUserSettings(
      conversationId: _requiredString(map['conversation_id']),
      userId: _requiredString(map['user_id']),
      isArchived: map['is_archived'] as bool? ?? false,
      isPinned: map['is_pinned'] as bool? ?? false,
      muteUntil: _date(map['mute_until']),
      notificationLevel: _string(map['notification_level']) ?? 'all',
      customTitle: _string(map['custom_title']),
      draft: _string(map['draft']),
      autoDeleteSeconds: seconds,
      protectedContent: map['protected_content'] as bool? ?? false,
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  factory ConversationUserSettings.defaults({
    required String conversationId,
    required String userId,
  }) {
    return ConversationUserSettings(
      conversationId: conversationId,
      userId: userId,
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final result = _string(value);
  if (result == null || result.isEmpty) {
    throw const FormatException('Некорректные настройки беседы.');
  }
  return result;
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
