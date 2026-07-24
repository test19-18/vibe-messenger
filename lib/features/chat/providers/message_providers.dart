import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/message_repository.dart';
import '../domain/chat_message.dart';
import '../domain/message_details.dart';
import '../services/message_service.dart';
import '../services/typing_service.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(supabaseClientProvider));
});

final messageServiceProvider = Provider<MessageService>((ref) {
  return MessageService(ref.watch(messageRepositoryProvider));
});

final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) {
      return ref.watch(messageRepositoryProvider).watchMessages(conversationId);
    });

final messageAttachmentsProvider = FutureProvider.autoDispose
    .family<Map<String, MessageAttachment>, String>((ref, conversationId) {
      return ref
          .watch(messageRepositoryProvider)
          .listAttachments(conversationId);
    });

final messageReactionsProvider = StreamProvider.autoDispose
    .family<List<MessageReaction>, String>((ref, conversationId) {
      return ref
          .watch(messageRepositoryProvider)
          .watchReactions(conversationId);
    });

final readReceiptsProvider = StreamProvider.autoDispose
    .family<List<ConversationReadReceipt>, String>((ref, conversationId) {
      return ref
          .watch(messageRepositoryProvider)
          .watchReadReceipts(conversationId);
    });

final pinnedMessageIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, conversationId) {
      return ref
          .watch(messageRepositoryProvider)
          .watchPinnedMessageIds(conversationId);
    });

final conversationPollsProvider = FutureProvider.autoDispose
    .family<Map<String, PollDetails>, String>((ref, conversationId) {
      return ref.watch(messageRepositoryProvider).listPolls(conversationId);
    });

final messageMutationProvider = StateNotifierProvider.autoDispose
    .family<MessageMutationController, AsyncValue<void>, String>((
      ref,
      conversationId,
    ) {
      final user = ref.watch(currentUserProvider);
      return MessageMutationController(
        service: ref.watch(messageServiceProvider),
        conversationId: conversationId,
        currentUserId: user?.id,
      );
    });

final typingServiceProvider = Provider.autoDispose
    .family<TypingService, String>((ref, conversationId) {
      final service = TypingService(
        client: ref.watch(supabaseClientProvider),
        conversationId: conversationId,
        currentUserId: ref.watch(currentUserProvider)?.id,
      );
      ref.onDispose(service.dispose);
      return service;
    });

final typingUsersProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, conversationId) {
      return ref.watch(typingServiceProvider(conversationId)).users;
    });

final pollMutationProvider = StateNotifierProvider.autoDispose
    .family<PollMutationController, AsyncValue<void>, String>((
      ref,
      conversationId,
    ) {
      return PollMutationController(
        repository: ref.watch(messageRepositoryProvider),
        conversationId: conversationId,
        currentUserId: ref.watch(currentUserProvider)?.id,
        onChanged: () {
          ref.invalidate(conversationPollsProvider(conversationId));
          ref.invalidate(messagesProvider(conversationId));
        },
      );
    });

class PollMutationController extends StateNotifier<AsyncValue<void>> {
  PollMutationController({
    required this.repository,
    required this.conversationId,
    required this.currentUserId,
    required this.onChanged,
  }) : super(const AsyncData(null));

  final MessageRepository repository;
  final String conversationId;
  final String? currentUserId;
  final void Function() onChanged;

  Future<bool> create({
    required String question,
    required List<String> options,
    required bool allowMultiple,
    required int maxSelections,
    required bool isAnonymous,
    DateTime? closesAt,
  }) {
    return _run(() async {
      await repository.createPoll(
        conversationId: conversationId,
        question: question,
        options: options,
        allowMultiple: allowMultiple,
        maxSelections: maxSelections,
        isAnonymous: isAnonymous,
        closesAt: closesAt,
      );
    });
  }

  Future<bool> vote(PollDetails poll, PollOption option) {
    final userId = currentUserId;
    if (userId == null) {
      state = AsyncError(
        const BackendUnavailableException('Нет сессии.'),
        StackTrace.current,
      );
      return Future.value(false);
    }
    return _run(() async {
      if (!poll.allowMultiple && !option.selectedByMe) {
        for (final selected in poll.options.where(
          (candidate) => candidate.selectedByMe,
        )) {
          await repository.vote(
            pollId: poll.id,
            optionId: selected.id,
            conversationId: conversationId,
            voterId: userId,
            selected: true,
          );
        }
      }
      await repository.vote(
        pollId: poll.id,
        optionId: option.id,
        conversationId: conversationId,
        voterId: userId,
        selected: option.selectedByMe,
      );
    });
  }

  Future<bool> _run(Future<void> Function() operation) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(operation);
    if (!mounted) {
      return false;
    }
    state = result;
    if (!result.hasError) {
      onChanged();
    }
    return !result.hasError;
  }
}

class MessageMutationController extends StateNotifier<AsyncValue<void>> {
  MessageMutationController({
    required this.service,
    required this.conversationId,
    required this.currentUserId,
  }) : super(const AsyncData(null));

  final MessageService service;
  final String conversationId;
  final String? currentUserId;

  String get _requiredUserId =>
      currentUserId ?? (throw const BackendUnavailableException('Нет сессии.'));

  Future<bool> send(String body, {String? replyToId}) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await service.send(
        conversationId: conversationId,
        senderId: _requiredUserId,
        body: body,
        replyToId: replyToId,
      );
    });
    if (!mounted) {
      return false;
    }
    state = result;
    return !result.hasError;
  }

  Future<bool> edit(ChatMessage message, String body) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => service.edit(
        messageId: message.id,
        senderId: _requiredUserId,
        body: body,
      ),
    );
    if (!mounted) {
      return false;
    }
    state = result;
    return !result.hasError;
  }

  Future<bool> delete(ChatMessage message) async {
    return _run(
      () => service.delete(messageId: message.id, senderId: _requiredUserId),
    );
  }

  Future<bool> uploadAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required MessageKind kind,
    String? body,
    String? replyToId,
    int? durationMs,
  }) async {
    final success = await _run(() async {
      await service.uploadAttachment(
        conversationId: conversationId,
        senderId: _requiredUserId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        kind: kind,
        body: body,
        replyToId: replyToId,
        durationMs: durationMs,
      );
    });
    return success;
  }

  Future<bool> sendLocation({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    return _run(
      () => service.sendLocation(
        conversationId: conversationId,
        senderId: _requiredUserId,
        latitude: latitude,
        longitude: longitude,
        label: label,
      ),
    );
  }

  Future<bool> sendContact({required String name, required String value}) {
    return _run(
      () => service.sendContact(
        conversationId: conversationId,
        senderId: _requiredUserId,
        name: name,
        value: value,
      ),
    );
  }

  Future<bool> toggleReaction({
    required ChatMessage message,
    required String emoji,
    required bool selected,
  }) {
    return _run(
      () => service.toggleReaction(
        messageId: message.id,
        userId: _requiredUserId,
        emoji: emoji,
        selected: selected,
      ),
    );
  }

  Future<bool> setPinned(ChatMessage message, {required bool pinned}) {
    return _run(
      () => service.setPinned(
        conversationId: conversationId,
        messageId: message.id,
        userId: _requiredUserId,
        pinned: pinned,
      ),
    );
  }

  Future<bool> forward(
    List<ChatMessage> messages,
    String targetConversationId,
  ) {
    return _run(
      () => service.forward(
        messages: messages,
        targetConversationId: targetConversationId,
        senderId: _requiredUserId,
      ),
    );
  }

  Future<bool> _run(Future<void> Function() operation) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(operation);
    if (!mounted) {
      return false;
    }
    state = result;
    return !result.hasError;
  }
}
