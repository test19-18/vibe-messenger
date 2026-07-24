import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../auth/providers/auth_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../domain/group_models.dart';
import '../providers/group_providers.dart';

class GroupDetailsScreen extends ConsumerWidget {
  const GroupDetailsScreen({required this.conversationId, super.key});

  final String conversationId;

  Future<void> _edit(BuildContext context, GroupDetails group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GroupEditSheet(group: group),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(groupDetailsProvider(conversationId));
    final members = ref.watch(groupMembersProvider(conversationId));
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final canManage =
        members.valueOrNull?.any(
          (member) =>
              member.userId == currentUserId &&
              member.status == 'active' &&
              member.isAdmin,
        ) ??
        false;

    ref.listen<AsyncValue<String?>>(groupMutationProvider(conversationId), (
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
          title: details.maybeWhen(
            data: (group) => Text(group.title),
            orElse: () => Text(context.tr(ru: 'Группа', en: 'Group')),
          ),
          actions: [
            if (canManage)
              details.maybeWhen(
                data: (group) => IconButton(
                  onPressed: () => _edit(context, group),
                  icon: const Icon(Icons.edit_rounded),
                  tooltip: context.tr(ru: 'Редактировать', en: 'Edit'),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            IconButton(
              onPressed: () => context.pushNamed(
                'conversation',
                pathParameters: {'conversationId': conversationId},
                queryParameters: {'group': 'true'},
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              tooltip: context.tr(ru: 'Открыть чат', en: 'Open chat'),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                text: context.tr(ru: 'О группе', en: 'About'),
              ),
              Tab(
                text: context.tr(ru: 'Участники', en: 'Members'),
              ),
              Tab(
                text: context.tr(ru: 'Заявки', en: 'Requests'),
              ),
              Tab(
                text: context.tr(ru: 'Инвайты', en: 'Invites'),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _AboutTab(details: details),
            _MembersTab(
              conversationId: conversationId,
              members: members,
              currentUserId: currentUserId,
              canManage: canManage,
            ),
            _RequestsTab(conversationId: conversationId, canManage: canManage),
            _InvitesTab(conversationId: conversationId, canManage: canManage),
          ],
        ),
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.details});

  final AsyncValue<GroupDetails> details;

  @override
  Widget build(BuildContext context) {
    return AsyncStateView<GroupDetails>(
      value: details,
      emptyTitle: context.tr(ru: 'Группа не найдена', en: 'Group not found'),
      emptyMessage: context.tr(
        ru: 'Возможно, доступ был отозван.',
        en: 'Your access may have been revoked.',
      ),
      dataBuilder: (context, group) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: AppAvatar(
              label: group.title,
              imageUrl: group.avatarUrl,
              seed: group.id,
              radius: 54,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            group.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (group.description?.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(group.description!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: Text(
                    group.isLocked
                        ? context.tr(
                            ru: 'Сообщения только для админов',
                            en: 'Admins can send messages',
                          )
                        : context.tr(
                            ru: 'Все участники могут писать',
                            en: 'All members can send messages',
                          ),
                  ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.how_to_reg_outlined),
                  title: Text(
                    group.joinRequestsEnabled
                        ? context.tr(
                            ru: 'Заявки на вступление включены',
                            en: 'Join requests enabled',
                          )
                        : context.tr(
                            ru: 'Вступление только по приглашению',
                            en: 'Invite only',
                          ),
                  ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.schedule_send_outlined),
                  title: Text(
                    context.tr(
                      ru: 'Отложенная отправка и автоудаление',
                      en: 'Scheduled send and auto-delete',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      ru: 'Не поддержаны текущей схемой; fake success не используется.',
                      en: 'Not supported by the current schema; no fake success is shown.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab({
    required this.conversationId,
    required this.members,
    required this.currentUserId,
    required this.canManage,
  });

  final String conversationId;
  final AsyncValue<List<GroupMember>> members;
  final String? currentUserId;
  final bool canManage;

  Future<void> _editLocalTag(
    BuildContext context,
    WidgetRef ref,
    GroupMember member,
  ) async {
    final controller = TextEditingController(text: member.localTag);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Локальная метка', en: 'Local tag')),
        content: TextField(
          controller: controller,
          maxLength: 40,
          decoration: InputDecoration(
            helperText: context.tr(
              ru: 'Хранится только на этом устройстве; поля в DB нет.',
              en: 'Stored only on this device; the DB has no tag column.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr(ru: 'Сохранить', en: 'Save')),
          ),
        ],
      ),
    );
    if (save == true) {
      await ref
          .read(groupMutationProvider(conversationId).notifier)
          .saveLocalTag(member.userId, controller.text);
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncStateView<List<GroupMember>>(
      value: members,
      isEmpty: (items) => items.isEmpty,
      emptyTitle: context.tr(ru: 'Нет участников', en: 'No members'),
      emptyMessage: context.tr(
        ru: 'Список участников недоступен.',
        en: 'Member list is unavailable.',
      ),
      onRetry: () => ref.invalidate(groupMembersProvider(conversationId)),
      dataBuilder: (context, items) => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, index) {
          final member = items[index];
          final profile = member.profile;
          return Card(
            child: ListTile(
              leading: AppAvatar(
                label: profile?.visibleName ?? 'Vibe',
                imageUrl: profile?.avatarUrl,
                seed: member.userId,
              ),
              title: Text(profile?.visibleName ?? member.userId),
              subtitle: Text(
                '${member.role} · ${member.status}'
                '${member.localTag == null ? '' : ' · ${member.localTag} (local)'}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  final controller = ref.read(
                    groupMutationProvider(conversationId).notifier,
                  );
                  switch (value) {
                    case 'tag':
                      await _editLocalTag(context, ref, member);
                      break;
                    case 'admin':
                      await controller.updateMember(
                        member.userId,
                        role: 'admin',
                      );
                      break;
                    case 'member':
                      await controller.updateMember(
                        member.userId,
                        role: 'member',
                      );
                      break;
                    case 'remove':
                      await controller.updateMember(
                        member.userId,
                        status: 'removed',
                      );
                      break;
                    case 'ban':
                      await controller.updateMember(
                        member.userId,
                        status: 'banned',
                      );
                      break;
                    case 'unban':
                      await controller.updateMember(
                        member.userId,
                        status: 'active',
                      );
                      break;
                    case 'owner':
                      await controller.transferOwnership(member.userId);
                      break;
                    case 'leave':
                      await controller.updateMember(
                        member.userId,
                        status: 'left',
                      );
                      if (context.mounted) {
                        context.go('/chats');
                      }
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'tag',
                    child: Text(
                      context.tr(ru: 'Локальная метка', en: 'Local tag'),
                    ),
                  ),
                  if (canManage && member.userId != currentUserId) ...[
                    PopupMenuItem(
                      value: member.role == 'admin' ? 'member' : 'admin',
                      child: Text(
                        member.role == 'admin'
                            ? context.tr(
                                ru: 'Сделать участником',
                                en: 'Make member',
                              )
                            : context.tr(
                                ru: 'Сделать админом',
                                en: 'Make admin',
                              ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(context.tr(ru: 'Удалить', en: 'Remove')),
                    ),
                    PopupMenuItem(
                      value: member.status == 'banned' ? 'unban' : 'ban',
                      child: Text(
                        member.status == 'banned'
                            ? context.tr(ru: 'Разбанить', en: 'Unban')
                            : context.tr(ru: 'Забанить', en: 'Ban'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'owner',
                      child: Text(
                        context.tr(
                          ru: 'Передать владение',
                          en: 'Transfer ownership',
                        ),
                      ),
                    ),
                  ],
                  if (member.userId == currentUserId && member.role != 'owner')
                    PopupMenuItem(
                      value: 'leave',
                      child: Text(
                        context.tr(ru: 'Покинуть группу', en: 'Leave group'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab({required this.conversationId, required this.canManage});

  final String conversationId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(groupJoinRequestsProvider(conversationId));
    return AsyncStateView<List<GroupJoinRequest>>(
      value: requests,
      isEmpty: (items) =>
          items.where((item) => item.status == 'pending').isEmpty,
      emptyTitle: context.tr(ru: 'Нет заявок', en: 'No requests'),
      emptyMessage: context.tr(
        ru: 'Новые заявки на вступление появятся здесь.',
        en: 'New join requests appear here.',
      ),
      onRetry: () => ref.invalidate(groupJoinRequestsProvider(conversationId)),
      dataBuilder: (context, items) {
        final pending = items
            .where((item) => item.status == 'pending')
            .toList();
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: pending.length,
          itemBuilder: (context, index) {
            final request = pending[index];
            return Card(
              child: ListTile(
                title: Text(
                  request.profile?.visibleName ?? request.requesterId,
                ),
                subtitle: Text(request.message ?? ''),
                trailing: canManage
                    ? Wrap(
                        children: [
                          IconButton(
                            onPressed: () => ref
                                .read(
                                  groupMutationProvider(
                                    conversationId,
                                  ).notifier,
                                )
                                .reviewRequest(request.id, approve: true),
                            icon: const Icon(
                              Icons.check_rounded,
                              color: AppColors.success,
                            ),
                          ),
                          IconButton(
                            onPressed: () => ref
                                .read(
                                  groupMutationProvider(
                                    conversationId,
                                  ).notifier,
                                )
                                .reviewRequest(request.id, approve: false),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

class _InvitesTab extends ConsumerWidget {
  const _InvitesTab({required this.conversationId, required this.canManage});

  final String conversationId;
  final bool canManage;

  Future<void> _inviteUser(BuildContext context, WidgetRef ref) async {
    final profiles = await ref.read(contactsProvider.future);
    if (!context.mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: profiles.length,
          itemBuilder: (context, index) {
            final profile = profiles[index];
            return ListTile(
              leading: AppAvatar(
                label: profile.visibleName,
                imageUrl: profile.avatarUrl,
                seed: profile.id,
              ),
              title: Text(profile.visibleName),
              subtitle: Text(profile.handle),
              onTap: () {
                Navigator.pop(sheetContext);
                ref
                    .read(groupMutationProvider(conversationId).notifier)
                    .invite(profile.id);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _createLink(BuildContext context, WidgetRef ref) async {
    final link = await ref
        .read(groupMutationProvider(conversationId).notifier)
        .createLink(
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          maxUses: 25,
        );
    if (link == null || !context.mounted) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: link.uri));
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            context.tr(ru: 'Ссылка создана', en: 'Invite link created'),
          ),
          content: SelectableText(link.uri),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr(ru: 'Готово', en: 'Done')),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(groupInvitationsProvider(conversationId));
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _inviteUser(context, ref),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(context.tr(ru: 'Пригласить', en: 'Invite')),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _createLink(context, ref),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(context.tr(ru: 'Ссылка', en: 'Link')),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: AsyncStateView<List<GroupInvitation>>(
            value: invitations,
            isEmpty: (items) => items.isEmpty,
            emptyTitle: context.tr(ru: 'Нет приглашений', en: 'No invites'),
            emptyMessage: context.tr(
              ru: 'Пригласите человека или создайте ссылку.',
              en: 'Invite someone or create a link.',
            ),
            onRetry: () =>
                ref.invalidate(groupInvitationsProvider(conversationId)),
            dataBuilder: (context, items) => ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final invite = items[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      invite.inviteeId == null
                          ? Icons.link_rounded
                          : Icons.person_outline_rounded,
                    ),
                    title: Text(invite.inviteeId ?? 'Link ${invite.id}'),
                    subtitle: Text(
                      '${invite.status} · ${invite.useCount}/${invite.maxUses}',
                    ),
                    trailing: canManage && invite.status == 'pending'
                        ? IconButton(
                            onPressed: () => ref
                                .read(groupRepositoryProvider)
                                .updateInvitation(invite.id, 'revoked')
                                .then(
                                  (_) => ref.invalidate(
                                    groupInvitationsProvider(conversationId),
                                  ),
                                ),
                            icon: const Icon(Icons.link_off_rounded),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupEditSheet extends ConsumerStatefulWidget {
  const _GroupEditSheet({required this.group});

  final GroupDetails group;

  @override
  ConsumerState<_GroupEditSheet> createState() => _GroupEditSheetState();
}

class _GroupEditSheetState extends ConsumerState<_GroupEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late bool _locked;
  late bool _joinRequests;
  String? _avatarPath;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.group.title);
    _description = TextEditingController(text: widget.group.description);
    _locked = widget.group.isLocked;
    _joinRequests = widget.group.joinRequestsEnabled;
    _avatarPath = widget.group.avatarPath;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
      withData: true,
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.single;
    final bytes = file?.bytes;
    final userId = ref.read(currentUserProvider)?.id;
    if (file == null || bytes == null || userId == null) {
      return;
    }
    setState(() => _uploading = true);
    try {
      final path = await ref
          .read(groupRepositoryProvider)
          .uploadGroupAvatar(
            conversationId: widget.group.id,
            userId: userId,
            bytes: bytes,
            extension: file.extension ?? 'jpg',
            contentType: _imageMime(file.extension),
          );
      if (mounted) {
        setState(() => _avatarPath = path);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      return;
    }
    final success = await ref
        .read(groupMutationProvider(widget.group.id).notifier)
        .updateGroup(
          title: _title.text,
          description: _description.text,
          avatarPath: _avatarPath,
          isLocked: _locked,
          joinRequestsEnabled: _joinRequests,
        );
    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupMutationProvider(widget.group.id));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              context.tr(ru: 'Редактировать группу', en: 'Edit group'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _title,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Название', en: 'Name'),
              ),
            ),
            TextField(
              controller: _description,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Описание', en: 'Description'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickAvatar,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined),
              label: Text(
                context.tr(ru: 'Загрузить аватар', en: 'Upload avatar'),
              ),
            ),
            SwitchListTile.adaptive(
              value: _locked,
              onChanged: (value) => setState(() => _locked = value),
              title: Text(
                context.tr(
                  ru: 'Только админы могут писать',
                  en: 'Admins only posting',
                ),
              ),
            ),
            SwitchListTile.adaptive(
              value: _joinRequests,
              onChanged: (value) => setState(() => _joinRequests = value),
              title: Text(
                context.tr(ru: 'Разрешить заявки', en: 'Enable join requests'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: state.isLoading ? null : _save,
              child: Text(context.tr(ru: 'Сохранить', en: 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}

String _imageMime(String? extension) {
  return switch (extension?.toLowerCase()) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };
}
