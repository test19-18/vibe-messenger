import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../domain/conversation_summary.dart';
import '../providers/conversation_providers.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(conversationsProvider),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: AsyncStateView<List<ConversationSummary>>(
        value: conversations,
        isEmpty: (items) => items.isEmpty,
        emptyTitle: 'Здесь пока тихо',
        emptyMessage:
            'Выберите человека в контактах и начните первый разговор.',
        onRetry: () => ref.invalidate(conversationsProvider),
        dataBuilder: (context, items) {
          return RefreshIndicator(
            onRefresh: () => ref.refresh(conversationsProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                110,
              ),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final conversation = items[index];
                return _ConversationTile(
                  conversation: conversation,
                  onTap: () => context.pushNamed(
                    'conversation',
                    pathParameters: {'conversationId': conversation.id},
                    queryParameters: {'title': conversation.visibleTitle},
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/contacts'),
        backgroundColor: AppColors.electricBlue,
        foregroundColor: Colors.white,
        tooltip: 'Новый чат',
        child: const Icon(Icons.edit_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ConversationSummary conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timestamp = conversation.lastMessageAt ?? conversation.updatedAt;
    final now = DateTime.now();
    final sameDay =
        now.year == timestamp.year &&
        now.month == timestamp.month &&
        now.day == timestamp.day;
    final time = sameDay
        ? DateFormat('HH:mm').format(timestamp)
        : DateFormat('dd.MM').format(timestamp);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              AppAvatar(
                label: conversation.visibleTitle,
                imageUrl: conversation.visibleAvatarUrl,
                seed: conversation.id,
                radius: 27,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.visibleTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          time,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage ?? 'Новая беседа',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (conversation.unreadCount > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.electricBlue,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : '${conversation.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
