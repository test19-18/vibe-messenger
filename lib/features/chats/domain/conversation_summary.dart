import '../../profile/domain/user_profile.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.isGroup,
    required this.createdAt,
    required this.updatedAt,
    required this.unreadCount,
    this.title,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.peer,
    this.isArchived = false,
    this.isPinned = false,
    this.muteUntil,
    this.notificationLevel = 'all',
    this.customTitle,
    this.draft,
    this.autoDeleteSeconds,
    this.protectedContent = false,
    this.folderIds = const {},
  });

  final String id;
  final String? title;
  final String? avatarUrl;
  final bool isGroup;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final UserProfile? peer;
  final bool isArchived;
  final bool isPinned;
  final DateTime? muteUntil;
  final String notificationLevel;
  final String? customTitle;
  final String? draft;
  final int? autoDeleteSeconds;
  final bool protectedContent;
  final Set<String> folderIds;

  bool get isMuted => muteUntil?.isAfter(DateTime.now()) ?? false;

  String get visibleTitle {
    final personalTitle = customTitle?.trim();
    if (personalTitle != null && personalTitle.isNotEmpty) {
      return personalTitle;
    }
    final conversationTitle = title?.trim();
    if (conversationTitle != null && conversationTitle.isNotEmpty) {
      return conversationTitle;
    }
    if (!isGroup && peer != null) {
      return peer!.visibleName;
    }
    return isGroup ? 'Групповой чат' : 'Личный чат';
  }

  String? get visibleAvatarUrl => avatarUrl ?? peer?.avatarUrl;

  factory ConversationSummary.fromMap(
    Map<String, dynamic> map, {
    required int unreadCount,
    String? lastMessage,
    DateTime? lastMessageAt,
    String? avatarUrl,
    UserProfile? peer,
    Map<String, dynamic>? userSettings,
    Set<String> folderIds = const {},
  }) {
    final createdAt =
        _date(map['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    final kind = _requiredString(map['kind']);
    if (kind != 'direct' && kind != 'group' && kind != 'channel') {
      throw const FormatException('Некорректные данные беседы.');
    }
    return ConversationSummary(
      id: _requiredString(map['id']),
      title: _string(map['title']),
      avatarUrl: avatarUrl,
      isGroup: kind != 'direct',
      createdAt: createdAt,
      updatedAt: _date(map['updated_at']) ?? createdAt,
      unreadCount: unreadCount,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      peer: peer,
      isArchived: userSettings?['is_archived'] as bool? ?? false,
      isPinned: userSettings?['is_pinned'] as bool? ?? false,
      muteUntil: _date(userSettings?['mute_until']),
      notificationLevel: _string(userSettings?['notification_level']) ?? 'all',
      customTitle: _string(userSettings?['custom_title']),
      draft: _string(userSettings?['draft']),
      autoDeleteSeconds: (userSettings?['auto_delete_seconds'] as num?)
          ?.toInt(),
      protectedContent: userSettings?['protected_content'] as bool? ?? false,
      folderIds: Set.unmodifiable(folderIds),
    );
  }
}

String? _string(Object? value) => value is String ? value : null;

String _requiredString(Object? value) {
  final string = _string(value);
  if (string == null || string.isEmpty) {
    throw const FormatException('Некорректные данные беседы.');
  }
  return string;
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
