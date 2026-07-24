import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../auth/providers/auth_providers.dart';
import '../../chats/providers/conversation_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/providers/profile_providers.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  Future<void> _openConversation(
    BuildContext context,
    WidgetRef ref,
    UserProfile profile,
  ) async {
    final currentUserId = ref.read(currentUserProvider)?.id;
    if (currentUserId == null) {
      return;
    }
    final conversationId = await ref
        .read(directConversationControllerProvider.notifier)
        .create(currentUserId: currentUserId, otherUserId: profile.id);
    if (context.mounted && conversationId != null) {
      context.pushNamed(
        'conversation',
        pathParameters: {'conversationId': conversationId},
        queryParameters: {'title': profile.visibleName},
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final createState = ref.watch(directConversationControllerProvider);

    ref.listen<AsyncValue<String?>>(directConversationControllerProvider, (
      previous,
      next,
    ) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Контакты')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              onChanged: (value) =>
                  ref.read(contactsQueryProvider.notifier).state = value,
              decoration: const InputDecoration(
                hintText: 'Найти человека',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: AsyncStateView<List<UserProfile>>(
              value: contacts,
              isEmpty: (profiles) => profiles.isEmpty,
              emptyTitle: 'Контактов пока нет',
              emptyMessage:
                  'Когда в таблице profiles появятся пользователи, они будут здесь.',
              onRetry: () => ref.invalidate(contactsProvider),
              dataBuilder: (context, profiles) {
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(contactsProvider.future),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      110,
                    ),
                    itemCount: profiles.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        child: ListTile(
                          enabled: !createState.isLoading,
                          onTap: () => _openConversation(context, ref, profile),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AppAvatar(
                                label: profile.visibleName,
                                imageUrl: profile.avatarUrl,
                                seed: profile.id,
                              ),
                              if (profile.isOnline)
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 13,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.surface,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            profile.visibleName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            profile.handle.isNotEmpty
                                ? profile.handle
                                : profile.isOnline
                                ? 'в сети'
                                : 'недавно в Вайбе',
                          ),
                          trailing: createState.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chat_bubble_outline_rounded),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
