import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../../chat/domain/chat_message.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/chat_folder.dart';
import '../domain/conversation_summary.dart';
import '../domain/conversation_user_settings.dart';

class ConversationRepository {
  const ConversationRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  Future<List<ConversationSummary>> listConversations(String userId) async {
    final membershipRows = await _requiredClient
        .from('conversation_members')
        .select('conversation_id')
        .eq('user_id', userId)
        .eq('status', 'active');
    if (membershipRows.isEmpty) {
      return const [];
    }

    final conversationIds = membershipRows
        .map((row) => _requiredString(row['conversation_id']))
        .toSet()
        .toList();

    final results = await Future.wait([
      _requiredClient
          .from('conversations')
          .select()
          .inFilter('id', conversationIds),
      _requiredClient
          .from('messages')
          .select()
          .inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false)
          .limit(500),
      _requiredClient
          .from('conversation_members')
          .select(
            'conversation_id,user_id,status,'
            'profiles!conversation_members_user_id_fkey('
            'id,username,display_name,avatar_path,bio,created_at,updated_at,'
            'user_presence(last_seen_at,online_until))',
          )
          .inFilter('conversation_id', conversationIds)
          .eq('status', 'active'),
      _requiredClient
          .from('conversation_read_receipts')
          .select('conversation_id,last_read_at')
          .eq('user_id', userId)
          .inFilter('conversation_id', conversationIds),
      _requiredClient
          .from('conversation_user_settings')
          .select()
          .eq('user_id', userId)
          .inFilter('conversation_id', conversationIds),
      _requiredClient
          .from('chat_folder_conversations')
          .select('folder_id,conversation_id')
          .eq('user_id', userId)
          .inFilter('conversation_id', conversationIds),
    ]);

    final conversationRows = results[0];
    final messageRows = results[1];
    final allMemberRows = results[2];
    final receiptRows = results[3];
    final userSettingRows = results[4];
    final folderRows = results[5];
    final lastReadByConversation = <String, DateTime?>{
      for (final row in receiptRows)
        _requiredString(row['conversation_id']): _date(row['last_read_at']),
    };
    final settingsByConversation = <String, Map<String, dynamic>>{
      for (final row in userSettingRows)
        _requiredString(row['conversation_id']): row,
    };
    final folderIdsByConversation = <String, Set<String>>{};
    for (final row in folderRows) {
      folderIdsByConversation
          .putIfAbsent(
            _requiredString(row['conversation_id']),
            () => <String>{},
          )
          .add(_requiredString(row['folder_id']));
    }

    final latestByConversation = <String, ChatMessage>{};
    final unreadByConversation = <String, int>{};
    for (final row in messageRows) {
      final message = ChatMessage.fromMap(row);
      latestByConversation.putIfAbsent(message.conversationId, () => message);
      final lastRead = lastReadByConversation[message.conversationId];
      final unread =
          message.senderId != userId &&
          message.deletedAt == null &&
          (lastRead == null || message.createdAt.isAfter(lastRead));
      if (unread) {
        unreadByConversation.update(
          message.conversationId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final peerByConversation = <String, UserProfile>{};
    for (final row in allMemberRows) {
      if (row['user_id'] == userId) {
        continue;
      }
      final profileMap = _map(row['profiles']);
      if (profileMap != null) {
        final profile = UserProfile.fromMap(profileMap);
        final avatarUrl = await _signedAvatarUrl(profile.avatarPath);
        peerByConversation.putIfAbsent(
          _requiredString(row['conversation_id']),
          () => profile.copyWith(avatarUrl: avatarUrl),
        );
      }
    }

    final conversations =
        await Future.wait(
            conversationRows.where((row) => row['kind'] != 'channel').map((
              row,
            ) async {
              final id = _requiredString(row['id']);
              final latest = latestByConversation[id];
              final avatarUrl = await _signedAvatarUrl(
                _string(row['avatar_path']),
              );
              return ConversationSummary.fromMap(
                row,
                unreadCount: unreadByConversation[id] ?? 0,
                lastMessage: latest?.visibleBody,
                lastMessageAt: latest?.createdAt,
                avatarUrl: avatarUrl,
                peer: peerByConversation[id],
                userSettings: settingsByConversation[id],
                folderIds: folderIdsByConversation[id] ?? const {},
              );
            }),
          )
          ..sort((a, b) {
            if (a.isPinned != b.isPinned) {
              return a.isPinned ? -1 : 1;
            }
            final left = a.lastMessageAt ?? a.updatedAt;
            final right = b.lastMessageAt ?? b.updatedAt;
            return right.compareTo(left);
          });
    return conversations;
  }

  Future<String> createGroup({
    required String title,
    String? description,
  }) async {
    final response = await _requiredClient.rpc(
      'create_group_conversation',
      params: {'_title': title.trim(), '_description': _nullable(description)},
    );
    if (response is! String || response.isEmpty) {
      throw const FormatException('Backend не вернул идентификатор группы.');
    }
    return response;
  }

  Stream<ConversationUserSettings> watchConversationSettings({
    required String conversationId,
    required String userId,
  }) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('conversation_user_settings')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', conversationId)
        .map((rows) {
          final ownRows = rows
              .where((row) => row['user_id'] == userId)
              .toList();
          return ownRows.isEmpty
              ? ConversationUserSettings.defaults(
                  conversationId: conversationId,
                  userId: userId,
                )
              : ConversationUserSettings.fromMap(ownRows.single);
        });
  }

  Future<void> updateConversationSettings({
    required String conversationId,
    required String userId,
    bool? archived,
    bool? pinned,
    DateTime? muteUntil,
    bool clearMute = false,
    String? notificationLevel,
    String? customTitle,
    String? draft,
    int? autoDeleteSeconds,
    bool clearAutoDelete = false,
    bool? protectedContent,
  }) async {
    final values = <String, dynamic>{};
    if (archived != null) {
      values['is_archived'] = archived;
    }
    if (pinned != null) {
      values['is_pinned'] = pinned;
    }
    if (clearMute || muteUntil != null) {
      values['mute_until'] = clearMute
          ? null
          : muteUntil?.toUtc().toIso8601String();
    }
    if (notificationLevel != null) {
      values['notification_level'] = notificationLevel;
    }
    if (customTitle != null) {
      values['custom_title'] = _nullable(customTitle);
    }
    if (draft != null) {
      values['draft'] = _nullable(draft);
    }
    if (clearAutoDelete || autoDeleteSeconds != null) {
      if (autoDeleteSeconds != null &&
          (autoDeleteSeconds < 1 || autoDeleteSeconds > 31536000)) {
        throw const FormatException(
          'Таймер автоудаления должен быть от 1 секунды до 1 года.',
        );
      }
      values['auto_delete_seconds'] = clearAutoDelete
          ? null
          : autoDeleteSeconds;
    }
    if (protectedContent != null) {
      values['protected_content'] = protectedContent;
    }
    if (values.isEmpty) {
      return;
    }
    final updated = await _requiredClient
        .from('conversation_user_settings')
        .update(values)
        .eq('conversation_id', conversationId)
        .eq('user_id', userId)
        .select('conversation_id')
        .maybeSingle();
    if (updated == null) {
      await _requiredClient.from('conversation_user_settings').insert({
        'conversation_id': conversationId,
        'user_id': userId,
        ...values,
      });
    }
  }

  Future<List<ChatFolder>> listFolders(String userId) async {
    final rows = await _requiredClient
        .from('chat_folders')
        .select()
        .eq('user_id', userId)
        .order('sort_order');
    return rows.map(ChatFolder.fromMap).toList();
  }

  Future<ChatFolder> createFolder({
    required String userId,
    required String name,
    String? color,
    String? icon,
  }) async {
    final row = await _requiredClient
        .from('chat_folders')
        .insert({
          'user_id': userId,
          'name': name.trim(),
          'color': color,
          'icon': icon,
        })
        .select()
        .single();
    return ChatFolder.fromMap(row);
  }

  Future<void> deleteFolder(String folderId) async {
    await _requiredClient.from('chat_folders').delete().eq('id', folderId);
  }

  Future<void> setConversationFolder({
    required String folderId,
    required String conversationId,
    required String userId,
    required bool selected,
  }) async {
    if (selected) {
      await _requiredClient.from('chat_folder_conversations').insert({
        'folder_id': folderId,
        'conversation_id': conversationId,
        'user_id': userId,
      });
    } else {
      await _requiredClient
          .from('chat_folder_conversations')
          .delete()
          .eq('folder_id', folderId)
          .eq('conversation_id', conversationId)
          .eq('user_id', userId);
    }
  }

  Future<String> createDirectConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    if (currentUserId == otherUserId) {
      throw const FormatException('Нельзя создать чат с самим собой.');
    }

    final response = await _requiredClient.rpc(
      'create_direct_conversation',
      params: {'_other_user_id': otherUserId},
    );
    if (response is! String || response.isEmpty) {
      throw const FormatException('Backend не вернул идентификатор беседы.');
    }
    return response;
  }

  Future<String?> _signedAvatarUrl(String? path) async {
    final normalizedPath = path?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      return null;
    }
    try {
      return await _requiredClient.storage
          .from('avatars')
          .createSignedUrl(normalizedPath, 3600);
    } catch (_) {
      return null;
    }
  }
}

String? _string(Object? value) => value is String ? value : null;

String? _nullable(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _requiredString(Object? value) {
  final string = _string(value);
  if (string == null || string.isEmpty) {
    throw const FormatException('Некорректные данные беседы.');
  }
  return string;
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
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
