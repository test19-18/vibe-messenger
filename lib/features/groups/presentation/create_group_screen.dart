import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../providers/group_providers.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final id = await ref
        .read(groupCreationProvider.notifier)
        .create(_titleController.text, _descriptionController.text);
    if (mounted && id != null) {
      context.go('/group/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupCreationProvider);
    ref.listen<AsyncValue<String?>>(groupCreationProvider, (previous, next) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Новая группа', en: 'New group')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Icon(
                Icons.groups_rounded,
                size: 72,
                color: context.tokens.accent,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _titleController,
                maxLength: 120,
                autofocus: true,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return context.tr(
                      ru: 'Введите название',
                      en: 'Enter a name',
                    );
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: context.tr(ru: 'Название', en: 'Name'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _descriptionController,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: context.tr(ru: 'Описание', en: 'Description'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: state.isLoading ? null : _create,
                icon: state.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_rounded),
                label: Text(
                  context.tr(ru: 'Создать группу', en: 'Create group'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.tr(
                  ru: 'Вы станете владельцем. Участников можно пригласить после создания.',
                  en: 'You will become the owner. Members can be invited after creation.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
