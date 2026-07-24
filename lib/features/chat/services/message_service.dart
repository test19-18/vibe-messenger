import 'dart:typed_data';

import '../data/message_repository.dart';
import '../domain/chat_message.dart';
import '../domain/message_details.dart';
import '../domain/scheduled_message.dart';

class MessageService {
  const MessageService(this._repository);

  final MessageRepository _repository;

  Future<ChatMessage> send({
    required String conversationId,
    required String senderId,
    required String body,
    String? replyToId,
  }) {
    final normalized = _validateBody(body);
    return _repository.send(
      conversationId: conversationId,
      senderId: senderId,
      body: normalized,
      replyToId: replyToId,
    );
  }

  Future<void> edit({
    required String messageId,
    required String senderId,
    required String body,
  }) {
    final normalized = _validateBody(body);
    return _repository.edit(
      messageId: messageId,
      senderId: senderId,
      body: normalized,
    );
  }

  Future<void> delete({required String messageId, required String senderId}) {
    return _repository.softDelete(messageId: messageId, senderId: senderId);
  }

  Future<void> deleteForSelf({
    required String conversationId,
    required String messageId,
    required String userId,
  }) {
    return _repository.deleteForSelf(
      conversationId: conversationId,
      messageId: messageId,
      userId: userId,
    );
  }

  Future<ScheduledMessage> schedule({
    required String conversationId,
    required String body,
    required DateTime scheduledFor,
    required bool silent,
    String? replyToId,
  }) {
    final normalized = _validateBody(body);
    return _repository.createScheduledMessage(
      conversationId: conversationId,
      body: normalized,
      scheduledFor: scheduledFor,
      silent: silent,
      replyToId: replyToId,
    );
  }

  Future<bool> cancelScheduledMessage(String scheduledMessageId) {
    return _repository.cancelScheduledMessage(scheduledMessageId);
  }

  Future<void> markRead({
    required String conversationId,
    required String userId,
    String? lastReadMessageId,
  }) {
    return _repository.markRead(
      conversationId: conversationId,
      userId: userId,
      lastReadMessageId: lastReadMessageId,
    );
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
  }) {
    return _repository.uploadAttachment(
      conversationId: conversationId,
      senderId: senderId,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      kind: kind,
      body: body,
      replyToId: replyToId,
      durationMs: durationMs,
    );
  }

  Future<void> sendLocation({
    required String conversationId,
    required String senderId,
    required double latitude,
    required double longitude,
    String? label,
  }) {
    return _repository.sendLocation(
      conversationId: conversationId,
      senderId: senderId,
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
  }

  Future<void> sendContact({
    required String conversationId,
    required String senderId,
    required String name,
    required String value,
  }) {
    return _repository.sendContact(
      conversationId: conversationId,
      senderId: senderId,
      name: name,
      value: value,
    );
  }

  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
    required bool selected,
  }) {
    return _repository.toggleReaction(
      messageId: messageId,
      userId: userId,
      emoji: emoji,
      selected: selected,
    );
  }

  Future<void> setPinned({
    required String conversationId,
    required String messageId,
    required String userId,
    required bool pinned,
  }) {
    return _repository.setPinned(
      conversationId: conversationId,
      messageId: messageId,
      userId: userId,
      pinned: pinned,
    );
  }

  Future<void> forward({
    required List<ChatMessage> messages,
    required String targetConversationId,
    required String senderId,
  }) {
    return _repository.forwardMessages(
      messages: messages,
      targetConversationId: targetConversationId,
      senderId: senderId,
    );
  }

  String _validateBody(String body) {
    final normalized = body.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Сообщение не может быть пустым.');
    }
    if (normalized.length > 4000) {
      throw const FormatException('Сообщение длиннее 4000 символов.');
    }
    return normalized;
  }
}
