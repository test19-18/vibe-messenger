class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.userId,
    required this.name,
    required this.sortOrder,
    this.color,
    this.icon,
  });

  final String id;
  final String userId;
  final String name;
  final String? color;
  final String? icon;
  final int sortOrder;

  factory ChatFolder.fromMap(Map<String, dynamic> map) {
    return ChatFolder(
      id: _required(map['id']),
      userId: _required(map['user_id']),
      name: _required(map['name']),
      color: map['color'] as String?,
      icon: map['icon'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

String _required(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Некорректные данные папки.');
}
