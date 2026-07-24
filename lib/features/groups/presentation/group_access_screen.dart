import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/group_providers.dart';

class GroupAccessScreen extends ConsumerStatefulWidget {
  const GroupAccessScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<GroupAccessScreen> createState() => _GroupAccessScreenState();
}

class _GroupAccessScreenState extends ConsumerState<GroupAccessScreen> {
  late final TextEditingController _tokenController;
  final _conversationController = TextEditingController();
  final _messageController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _conversationController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _acceptToken() async {
    setState(() => _busy = true);
    try {
      final token = _tokenController.text.trim().replaceFirst(
        'vibe://group-invite/',
        '',
      );
      final id = await ref
          .read(groupRepositoryProvider)
          .acceptInviteToken(token);
      if (mounted) {
        context.go('/group/$id');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _requestJoin() async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(groupRepositoryProvider)
          .createJoinRequest(
            conversationId: _conversationController.text.trim(),
            requesterId: userId,
            message: _messageController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                ru: 'Заявка отправлена. Группа появится после одобрения.',
                en: 'Request sent. The group appears after approval.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitations =
        ref.watch(myGroupInvitationsProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Вступить в группу', en: 'Join a group')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (invitations.isNotEmpty) ...[
            Text(
              context.tr(ru: 'Ваши приглашения', en: 'Your invitations'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final invitation in invitations)
              Card(
                child: ListTile(
                  title: Text(
                    '${context.tr(ru: 'Группа', en: 'Group')} ${invitation.conversationId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(invitation.status),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final id = await ref
                                    .read(groupRepositoryProvider)
                                    .acceptInvitation(invitation.id);
                                if (context.mounted) {
                                  context.go('/group/$id');
                                }
                              },
                        icon: const Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                        ),
                      ),
                      IconButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await ref
                                    .read(groupRepositoryProvider)
                                    .updateInvitation(
                                      invitation.id,
                                      'declined',
                                    );
                                ref.invalidate(myGroupInvitationsProvider);
                              },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text(
            context.tr(ru: 'Ссылка-приглашение', en: 'Invite link'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _tokenController,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.tr(
                ru: 'Token или vibe:// ссылка',
                en: 'Token or vibe:// link',
              ),
              prefixIcon: const Icon(Icons.link_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _busy ? null : _acceptToken,
            child: Text(
              context.tr(ru: 'Принять приглашение', en: 'Accept invite'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            context.tr(ru: 'Заявка по ID группы', en: 'Request by group ID'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr(
              ru: 'Работает только если владелец включил заявки и вы знаете UUID группы.',
              en: 'Works only when join requests are enabled and you know the group UUID.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _conversationController,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.tr(ru: 'UUID группы', en: 'Group UUID'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _messageController,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: context.tr(ru: 'Сообщение', en: 'Message'),
            ),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _requestJoin,
            child: Text(context.tr(ru: 'Отправить заявку', en: 'Send request')),
          ),
        ],
      ),
    );
  }
}
