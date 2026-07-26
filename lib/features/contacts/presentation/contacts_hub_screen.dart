import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../auth/providers/auth_providers.dart';
import '../../chats/providers/conversation_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/providers/profile_providers.dart';
import '../domain/contact_relationship.dart';
import '../providers/contact_providers.dart';

class ContactsHubScreen extends ConsumerWidget {
  const ContactsHubScreen({super.key});

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

  Future<void> _reportUser(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final reason = TextEditingController();
    final details = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Пожаловаться', en: 'Report user')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reason,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Причина', en: 'Reason'),
              ),
            ),
            TextField(
              controller: details,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Подробности', en: 'Details'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Отправить', en: 'Submit')),
          ),
        ],
      ),
    );
    if (submit == true && context.mounted) {
      await ref
          .read(contactMutationProvider.notifier)
          .reportUser(userId, reason.text, details: details.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                ru: 'Жалоба отправлена на модерацию.',
                en: 'Report submitted for moderation.',
              ),
            ),
          ),
        );
      }
    }
    reason.dispose();
    details.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<void>>(contactMutationProvider, (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
      }
    });
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

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(ru: 'Контакты', en: 'Contacts')),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                text: context.tr(ru: 'Каталог', en: 'Directory'),
              ),
              Tab(
                text: context.tr(ru: 'Заявки', en: 'Requests'),
              ),
              Tab(
                text: context.tr(ru: 'Мои', en: 'Contacts'),
              ),
              Tab(
                text: context.tr(ru: 'Блокировки', en: 'Blocked'),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _DirectoryTab(
              onChat: (profile) => _openConversation(context, ref, profile),
              onReport: (profile) => _reportUser(context, ref, profile.id),
            ),
            const _RequestsTab(),
            _AcceptedContactsTab(
              onChat: (profile) => _openConversation(context, ref, profile),
              onReport: (profile) => _reportUser(context, ref, profile.id),
            ),
            const _BlockedTab(),
          ],
        ),
      ),
    );
  }
}

class _DirectoryTab extends ConsumerWidget {
  const _DirectoryTab({required this.onChat, required this.onReport});

  final ValueChanged<UserProfile> onChat;
  final ValueChanged<UserProfile> onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(contactsProvider);
    final relationships =
        ref.watch(contactRelationshipsProvider).valueOrNull ?? const [];
    final relatedIds = relationships
        .where(
          (relationship) =>
              relationship.status == ContactStatus.pending ||
              relationship.status == ContactStatus.accepted,
        )
        .map((relationship) => relationship.profile?.id)
        .whereType<String>()
        .toSet();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            onChanged: (value) =>
                ref.read(contactsQueryProvider.notifier).state = value,
            decoration: InputDecoration(
              hintText: context.tr(
                ru: 'Имя или @username',
                en: 'Name or @username',
              ),
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: AsyncStateView<List<UserProfile>>(
            value: profiles,
            isEmpty: (items) => items.isEmpty,
            emptyTitle: context.tr(
              ru: 'Никого не найдено',
              en: 'No people found',
            ),
            emptyMessage: context.tr(
              ru: 'Попробуйте изменить запрос.',
              en: 'Try another search query.',
            ),
            onRetry: () => ref.invalidate(contactsProvider),
            dataBuilder: (context, items) => RefreshIndicator(
              onRefresh: () => ref.refresh(contactsProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final profile = items[index];
                  final related = relatedIds.contains(profile.id);
                  return _ProfileTile(
                    profile: profile,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'request':
                            ref
                                .read(contactMutationProvider.notifier)
                                .sendRequest(profile.id);
                            break;
                          case 'chat':
                            onChat(profile);
                            break;
                          case 'block':
                            ref
                                .read(contactMutationProvider.notifier)
                                .block(profile.id);
                            break;
                          case 'report':
                            onReport(profile);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (!related)
                          PopupMenuItem(
                            value: 'request',
                            child: Text(
                              context.tr(
                                ru: 'Добавить в контакты',
                                en: 'Add contact',
                              ),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'chat',
                          child: Text(
                            context.tr(ru: 'Написать', en: 'Message'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'block',
                          child: Text(
                            context.tr(ru: 'Заблокировать', en: 'Block'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'report',
                          child: Text(
                            context.tr(ru: 'Пожаловаться', en: 'Report'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider)?.id;
    final relationships = ref.watch(contactRelationshipsProvider);
    return AsyncStateView<List<ContactRelationship>>(
      value: relationships,
      isEmpty: (items) =>
          items.where((item) => item.status == ContactStatus.pending).isEmpty,
      emptyTitle: context.tr(ru: 'Нет новых заявок', en: 'No requests'),
      emptyMessage: context.tr(
        ru: 'Входящие и исходящие заявки появятся здесь.',
        en: 'Incoming and outgoing requests appear here.',
      ),
      onRetry: () => ref.invalidate(contactRelationshipsProvider),
      dataBuilder: (context, items) {
        final pending = items
            .where((item) => item.status == ContactStatus.pending)
            .toList();
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: pending.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final relationship = pending[index];
            final incoming =
                userId != null && relationship.isIncomingFor(userId);
            return _RelationshipTile(
              relationship: relationship,
              subtitle: incoming
                  ? context.tr(ru: 'Входящая заявка', en: 'Incoming request')
                  : context.tr(ru: 'Ожидает ответа', en: 'Awaiting response'),
              trailing: incoming
                  ? Wrap(
                      children: [
                        IconButton(
                          onPressed: () => ref
                              .read(contactMutationProvider.notifier)
                              .updateStatus(
                                relationship.id,
                                ContactStatus.accepted,
                              ),
                          icon: Icon(
                            Icons.check_rounded,
                            color: context.tokens.success,
                          ),
                          tooltip: context.tr(ru: 'Принять', en: 'Accept'),
                        ),
                        IconButton(
                          onPressed: () => ref
                              .read(contactMutationProvider.notifier)
                              .updateStatus(
                                relationship.id,
                                ContactStatus.declined,
                              ),
                          icon: Icon(
                            Icons.close_rounded,
                            color: context.tokens.danger,
                          ),
                          tooltip: context.tr(ru: 'Отклонить', en: 'Decline'),
                        ),
                      ],
                    )
                  : IconButton(
                      onPressed: () => ref
                          .read(contactMutationProvider.notifier)
                          .updateStatus(
                            relationship.id,
                            ContactStatus.cancelled,
                          ),
                      icon: const Icon(Icons.cancel_outlined),
                      tooltip: context.tr(ru: 'Отменить', en: 'Cancel'),
                    ),
            );
          },
        );
      },
    );
  }
}

class _AcceptedContactsTab extends ConsumerWidget {
  const _AcceptedContactsTab({required this.onChat, required this.onReport});

  final ValueChanged<UserProfile> onChat;
  final ValueChanged<UserProfile> onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationships = ref.watch(contactRelationshipsProvider);
    return AsyncStateView<List<ContactRelationship>>(
      value: relationships,
      isEmpty: (items) =>
          items.where((item) => item.status == ContactStatus.accepted).isEmpty,
      emptyTitle: context.tr(ru: 'Контактов пока нет', en: 'No contacts yet'),
      emptyMessage: context.tr(
        ru: 'Отправьте заявку из каталога.',
        en: 'Send a request from the directory.',
      ),
      onRetry: () => ref.invalidate(contactRelationshipsProvider),
      dataBuilder: (context, items) {
        final accepted = items
            .where((item) => item.status == ContactStatus.accepted)
            .toList();
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: accepted.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
          itemBuilder: (context, index) {
            final relationship = accepted[index];
            final profile = relationship.profile;
            return _RelationshipTile(
              relationship: relationship,
              subtitle: profile?.handle ?? '',
              onTap: profile == null ? null : () => onChat(profile),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'remove') {
                    ref
                        .read(contactMutationProvider.notifier)
                        .remove(relationship.id);
                  } else if (value == 'block' && profile != null) {
                    ref
                        .read(contactMutationProvider.notifier)
                        .block(profile.id);
                  } else if (value == 'report' && profile != null) {
                    onReport(profile);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      context.tr(ru: 'Удалить контакт', en: 'Remove contact'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'block',
                    child: Text(context.tr(ru: 'Заблокировать', en: 'Block')),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Text(context.tr(ru: 'Пожаловаться', en: 'Report')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BlockedTab extends ConsumerWidget {
  const _BlockedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedUsersProvider);
    return AsyncStateView<List<BlockedUser>>(
      value: blocked,
      isEmpty: (items) => items.isEmpty,
      emptyTitle: context.tr(ru: 'Список пуст', en: 'No blocked users'),
      emptyMessage: context.tr(
        ru: 'Заблокированные пользователи появятся здесь.',
        en: 'Blocked users appear here.',
      ),
      onRetry: () => ref.invalidate(blockedUsersProvider),
      dataBuilder: (context, items) => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, index) {
          final blockedUser = items[index];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.block_rounded)),
              title: Text(blockedUser.userId),
              subtitle: Text(
                context.tr(
                  ru: 'Имя скрыто политикой RLS после блокировки',
                  en: 'Name is hidden by RLS after blocking',
                ),
              ),
              trailing: TextButton(
                onPressed: () => ref
                    .read(contactMutationProvider.notifier)
                    .unblock(blockedUser.userId),
                child: Text(context.tr(ru: 'Разблокировать', en: 'Unblock')),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.trailing});

  final UserProfile profile;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: AppAvatar(
          label: profile.visibleName,
          imageUrl: profile.avatarUrl,
          seed: profile.id,
        ),
        title: Text(profile.visibleName),
        subtitle: Text(
          profile.handle.isNotEmpty
              ? profile.handle
              : profile.isOnline
              ? context.tr(ru: 'в сети', en: 'online')
              : context.tr(ru: 'недавно', en: 'recently'),
        ),
        trailing: trailing,
      ),
    );
  }
}

class _RelationshipTile extends StatelessWidget {
  const _RelationshipTile({
    required this.relationship,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final ContactRelationship relationship;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final profile = relationship.profile;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: AppAvatar(
          label: profile?.visibleName ?? 'Vibe',
          imageUrl: profile?.avatarUrl,
          seed: profile?.id ?? relationship.id,
        ),
        title: Text(profile?.visibleName ?? 'Пользователь'),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }
}
