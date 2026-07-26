import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/user_profile.dart';
import '../providers/profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editProfile(BuildContext context, UserProfile profile) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.tokens.surface,
      showDragHandle: true,
      builder: (context) => _ProfileEditSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(myProfileProvider);
    final email = ref.watch(currentUserProvider)?.email ?? '';

    return Scaffold(
      backgroundColor: context.tokens.groupedBackground,
      appBar: AppBar(
        backgroundColor: context.tokens.groupedBackground,
        title: const Text('Профиль'),
        actions: [
          IconButton(
            onPressed: () => context.push('/profile/qr'),
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'QR профиля',
          ),
          profileState.maybeWhen(
            data: (profile) => IconButton(
              onPressed: () => _editProfile(context, profile),
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Редактировать',
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: AsyncStateView<UserProfile>(
        value: profileState,
        emptyTitle: 'Профиль не найден',
        emptyMessage: 'Создайте строку profiles для текущего пользователя.',
        onRetry: () => ref.invalidate(myProfileProvider),
        dataBuilder: (context, profile) {
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myProfileProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              children: [
                _ProfileHeader(profile: profile),
                const SizedBox(height: AppSpacing.lg),
                SectionCard(
                  children: [
                    VibeListTile(
                      icon: Icons.alternate_email_rounded,
                      iconColor: context.tokens.accent,
                      title: email.isEmpty ? 'Email не указан' : email,
                      subtitle: 'Email аккаунта',
                      trailing: const SizedBox.shrink(),
                    ),
                    const SectionDivider(),
                    VibeListTile(
                      icon: Icons.badge_outlined,
                      iconColor: context.tokens.accentSecondary,
                      title: profile.handle.isEmpty
                          ? 'Имя пользователя не задано'
                          : profile.handle,
                      subtitle: 'Публичный username',
                      trailing: const SizedBox.shrink(),
                    ),
                    const SectionDivider(),
                    VibeListTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: context.tokens.accentCyan,
                      title: profile.bio?.trim().isNotEmpty == true
                          ? profile.bio!
                          : 'Расскажите немного о себе',
                      subtitle: 'Описание',
                      trailing: const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () => _editProfile(context, profile),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Редактировать профиль'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.tokens.surfaceElevated, context.tokens.surface],
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: context.tokens.separator),
      ),
      child: Column(
        children: [
          AppAvatar(
            label: profile.visibleName,
            imageUrl: profile.avatarUrl,
            seed: profile.id,
            radius: 48,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            profile.visibleName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (profile.handle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(profile.handle, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:
                  (profile.isOnline
                          ? context.tokens.success
                          : context.tokens.textSecondary)
                      .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              profile.isOnline ? 'в сети' : 'профиль Вайба',
              style: TextStyle(
                color: profile.isOnline
                    ? context.tokens.success
                    : context.tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileEditSheet extends ConsumerStatefulWidget {
  const _ProfileEditSheet({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<_ProfileEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late String? _avatarPath;
  bool _avatarUploading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _usernameController = TextEditingController(text: widget.profile.username);
    _bioController = TextEditingController(text: widget.profile.bio);
    _avatarPath = widget.profile.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) {
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать выбранный файл.')),
      );
      return;
    }
    setState(() => _avatarUploading = true);
    final extension = file.extension ?? 'jpg';
    final path = await ref
        .read(profileEditorProvider.notifier)
        .uploadAvatar(
          userId: widget.profile.id,
          bytes: bytes,
          extension: extension,
          contentType: _imageMime(extension),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _avatarUploading = false;
      if (path != null) {
        _avatarPath = path;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final updated = widget.profile.copyWith(
      displayName: _nameController.text.trim(),
      username: _usernameController.text.trim(),
      bio: _bioController.text.trim(),
      avatarPath: _avatarPath ?? '',
    );
    final success = await ref
        .read(profileEditorProvider.notifier)
        .save(updated);
    if (mounted && success) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editState = ref.watch(profileEditorProvider);

    ref.listen<AsyncValue<UserProfile?>>(profileEditorProvider, (
      previous,
      next,
    ) {
      if (next.hasError && previous?.error != next.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(next.error!))));
      }
    });

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Редактировать профиль',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: Validators.displayName,
                decoration: const InputDecoration(labelText: 'Имя'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _usernameController,
                autocorrect: false,
                validator: Validators.username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _bioController,
                minLines: 2,
                maxLines: 4,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'О себе'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _avatarUploading || editState.isLoading
                    ? null
                    : _pickAvatar,
                icon: _avatarUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_back_outlined),
                label: Text(
                  _avatarPath == null ? 'Выбрать аватар' : 'Заменить аватар',
                ),
              ),
              if (_avatarPath != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Приватный Storage: $_avatarPath',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: editState.isLoading ? null : _save,
                child: editState.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _imageMime(String extension) {
  return switch (extension.toLowerCase()) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };
}
