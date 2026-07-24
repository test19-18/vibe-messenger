import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../domain/chat_message.dart';
import '../domain/message_details.dart';

class MessageRepository {
  const MessageRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) {
          final messages = rows.map(ChatMessage.fromMap).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return messages;
        });
  }

  Future<ChatMessage> send({
    required String conversationId,
    required String senderId,
    required String body,
    MessageKind kind = MessageKind.text,
    Map<String, dynamic> metadata = const {},
    String? replyToId,
    String? clientNonce,
  }) async {
    final response = await _requiredClient
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': senderId,
          'kind': kind.name,
          'body': body.trim().isEmpty ? null : body.trim(),
          'metadata': metadata,
          'reply_to_message_id': replyToId,
          'client_nonce': clientNonce ?? _nonce(),
        })
        .select()
        .single();
    return ChatMessage.fromMap(response);
  }

  Future<void> edit({
    required String messageId,
    required String senderId,
    required String body,
  }) async {
    await _requiredClient
        .from('messages')
        .update({'body': body.trim()})
        .eq('id', messageId)
        .eq('sender_id', senderId);
  }

  Future<void> softDelete({
    required String messageId,
    required String senderId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _requiredClient
        .from('messages')
        .update({'deleted_at': now})
        .eq('id', messageId)
        .eq('sender_id', senderId);
  }

  Future<void> markRead({
    required String conversationId,
    required String userId,
    String? lastReadMessageId,
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final values = <String, dynamic>{'last_read_at': timestamp};
    if (lastReadMessageId != null) {
      values['last_read_message_id'] = lastReadMessageId;
    }
    final updated = await _requiredClient
        .from('conversation_read_receipts')
        .update(values)
        .eq('conversation_id', conversationId)
        .eq('user_id', userId)
        .select('conversation_id')
        .maybeSingle();
    if (updated == null) {
      await _requiredClient.from('conversation_read_receipts').insert({
        'conversation_id': conversationId,
        'user_id': userId,
        ...values,
      });
    }
  }

  Stream<List<MessageReaction>> watchReactions(String conversationId) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('message_reactions')
        .stream(primaryKey: ['message_id', 'user_id', 'emoji'])
        .map((rows) => rows.map(MessageReaction.fromMap).toList());
  }

  Stream<List<ConversationReadReceipt>> watchReadReceipts(
    String conversationId,
  ) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('conversation_read_receipts')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', conversationId)
        .map((rows) => rows.map(ConversationReadReceipt.fromMap).toList());
  }

  Stream<Set<String>> watchPinnedMessageIds(String conversationId) {
    if (_client == null) {
      return Stream.error(const BackendUnavailableException());
    }
    return _requiredClient
        .from('message_pins')
        .stream(primaryKey: ['conversation_id', 'message_id'])
        .eq('conversation_id', conversationId)
        .map(
          (rows) =>
              rows.map((row) => row['message_id']).whereType<String>().toSet(),
        );
  }

  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
    required bool selected,
  }) async {
    if (selected) {
      await _requiredClient
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('emoji', emoji);
    } else {
      await _requiredClient.from('message_reactions').insert({
        'message_id': messageId,
        'user_id': userId,
        'emoji': emoji,
      });
    }
  }

  Future<void> setPinned({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool pinned,
  }) async {
    if (pinned) {
      await _requiredClient.from('message_pins').insert({
        'conversation_id': conversationId,
        'message_id': messageId,
        'pinned_by': userId,
      });
    } else {
      await _requiredClient
          .from('message_pins')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('message_id', messageId);
    }
  }

  Future<List<ChatMessage>> searchMessages({
    required String conversationId,
    required String query,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final escaped = normalized.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final rows = await _requiredClient
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .isFilter('deleted_at', null)
        .ilike('body', '%$escaped%')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<MessageAttachment> uploadAttachment({
    required String conversationId,
    required String senderId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required MessageKind kind,
    String? body,
    String? replyToId,
    int? durationMs,
  }) async {
    if (!const {
      MessageKind.image,
      MessageKind.video,
      MessageKind.file,
      MessageKind.audio,
      MessageKind.voice,
    }.contains(kind)) {
      throw const FormatException('Этот тип сообщения не поддерживает файл.');
    }
    final maxBytes = kind == MessageKind.voice
        ? 50 * 1024 * 1024
        : 100 * 1024 * 1024;
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw FormatException(
        'Файл пуст или превышает ${kind == MessageKind.voice ? 50 : 100} МБ.',
      );
    }
    final bucket = kind == MessageKind.voice ? 'voice-messages' : 'chat-media';
    final safeName = _safeFileName(fileName);
    final storagePath =
        '$conversationId/$senderId/'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-$safeName';
    await _requiredClient.storage
        .from(bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    ChatMessage? createdMessage;
    try {
      final message = await send(
        conversationId: conversationId,
        senderId: senderId,
        body: body ?? '',
        kind: kind,
        replyToId: replyToId,
        metadata: {'file_name': fileName},
      );
      createdMessage = message;
      final row = await _requiredClient
          .from('message_attachments')
          .insert({
            'message_id': message.id,
            'conversation_id': conversationId,
            'uploaded_by': senderId,
            'kind': kind.name,
            'storage_bucket': bucket,
            'storage_path': storagePath,
            'file_name': fileName,
            'mime_type': mimeType,
            'byte_size': bytes.length,
            'duration_ms': durationMs,
          })
          .select()
          .single();
      final url = await _requiredClient.storage
          .from(bucket)
          .createSignedUrl(storagePath, 3600);
      return MessageAttachment.fromMap(row, signedUrl: url);
    } catch (_) {
      if (createdMessage != null) {
        try {
          await softDelete(messageId: createdMessage.id, senderId: senderId);
        } catch (_) {
          // The original failure is more useful; backend cleanup handles residue.
        }
      }
      try {
        await _requiredClient.storage.from(bucket).remove([storagePath]);
      } catch (_) {
        // A periodic backend cleanup must remove any orphan if this retry fails.
      }
      rethrow;
    }
  }

  Future<Map<String, MessageAttachment>> listAttachments(
    String conversationId,
  ) async {
    final rows = await _requiredClient
        .from('message_attachments')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    final result = <String, MessageAttachment>{};
    for (final row in rows) {
      final parsed = MessageAttachment.fromMap(row);
      String? url;
      try {
        url = await _requiredClient.storage
            .from(parsed.storageBucket)
            .createSignedUrl(parsed.storagePath, 3600);
      } catch (_) {
        url = null;
      }
      result[parsed.messageId] = parsed.copyWith(signedUrl: url);
    }
    return result;
  }

  Future<Uint8List> downloadAttachment(MessageAttachment attachment) {
    return _requiredClient.storage
        .from(attachment.storageBucket)
        .download(attachment.storagePath);
  }

  Future<void> sendLocation({
    required String conversationId,
    required String senderId,
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Некорректные координаты.');
    }
    await send(
      conversationId: conversationId,
      senderId: senderId,
      body: label ?? '',
      kind: MessageKind.location,
      metadata: {'latitude': latitude, 'longitude': longitude, 'label': label},
    );
  }

  Future<void> sendContact({
    required String conversationId,
    required String senderId,
    required String name,
    required String value,
  }) async {
    if (name.trim().isEmpty || value.trim().isEmpty) {
      throw const FormatException('Укажите имя и телефон или email.');
    }
    await send(
      conversationId: conversationId,
      senderId: senderId,
      body: name.trim(),
      kind: MessageKind.contact,
      metadata: {'name': name.trim(), 'value': value.trim()},
    );
  }

  Future<void> forwardMessages({
    required List<ChatMessage> messages,
    required String targetConversationId,
    required String senderId,
  }) async {
    for (final message in messages.where((item) => !item.isDeleted)) {
      if (message.kind == MessageKind.poll ||
          message.kind == MessageKind.system ||
          const {
            MessageKind.image,
            MessageKind.video,
            MessageKind.file,
            MessageKind.audio,
            MessageKind.voice,
          }.contains(message.kind)) {
        throw const FormatException(
          'Пересылка poll/media требует серверного copy RPC и пока недоступна.',
        );
      }
      await send(
        conversationId: targetConversationId,
        senderId: senderId,
        body: message.body,
        kind: message.kind,
        metadata: {
          ...message.metadata,
          'forwarded_from_message_id': message.id,
          'forwarded_from_conversation_id': message.conversationId,
        },
      );
    }
  }

  Future<PollDetails> createPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    required bool allowMultiple,
    required int maxSelections,
    required bool isAnonymous,
    DateTime? closesAt,
  }) async {
    final response = await _requiredClient.rpc(
      'create_poll',
      params: {
        '_conversation_id': conversationId,
        '_question': question.trim(),
        '_options': options.map((option) => option.trim()).toList(),
        '_allow_multiple': allowMultiple,
        '_max_selections': maxSelections,
        '_is_anonymous': isAnonymous,
        '_closes_at': closesAt?.toUtc().toIso8601String(),
      },
    );
    if (response is! String) {
      throw const FormatException('Backend не вернул идентификатор опроса.');
    }
    return getPoll(response);
  }

  Future<PollDetails> getPoll(String pollId) async {
    final row = await _requiredClient
        .from('polls')
        .select()
        .eq('id', pollId)
        .single();
    final results = await _requiredClient.rpc(
      'get_poll_results',
      params: {'_poll_id': pollId},
    );
    final options = results is List
        ? results
              .whereType<Map>()
              .map(
                (item) => PollOption.fromMap(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <PollOption>[];
    return PollDetails.fromMap(row, options: options);
  }

  Future<Map<String, PollDetails>> listPolls(String conversationId) async {
    final rows = await _requiredClient
        .from('polls')
        .select()
        .eq('conversation_id', conversationId);
    final result = <String, PollDetails>{};
    for (final row in rows) {
      final poll = await getPoll(row['id'] as String);
      result[poll.messageId] = poll;
    }
    return result;
  }

  Future<void> vote({
    required String pollId,
    required String optionId,
    required String conversationId,
    required String voterId,
    required bool selected,
  }) async {
    if (selected) {
      await _requiredClient
          .from('poll_votes')
          .delete()
          .eq('poll_id', pollId)
          .eq('option_id', optionId)
          .eq('voter_id', voterId);
    } else {
      await _requiredClient.from('poll_votes').insert({
        'poll_id': pollId,
        'option_id': optionId,
        'conversation_id': conversationId,
        'voter_id': voterId,
      });
    }
  }
}

String _nonce() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(18, (_) => random.nextInt(256)));
}

String _safeFileName(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return safe.isEmpty ? 'file' : safe.substring(0, min(safe.length, 180));
}
