import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/backend_status_banner.dart';
import '../../../core/widgets/section_card.dart';
import '../../auth/providers/auth_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notifications = true;
  bool _messagePreview = true;
  bool _compactMode = false;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.tokens.surfaceElevated,
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Локальная сессия будет удалена с устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Выйти',
              style: TextStyle(color: context.tokens.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await ref
        .read(authControllerProvider(AuthAction.signOut).notifier)
        .signOut();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider(AuthAction.signOut));

    ref.listen<AsyncValue<void>>(authControllerProvider(AuthAction.signOut), (
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
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        children: [
          const BackendStatusBanner(),
          const SizedBox(height: AppSpacing.md),
          _SectionLabel(label: 'Уведомления'),
          SectionCard(
            children: [
              SwitchListTile.adaptive(
                value: _notifications,
                onChanged: (value) => setState(() => _notifications = value),
                secondary: _SettingsIcon(
                  icon: Icons.notifications_rounded,
                  color: context.tokens.accent,
                ),
                title: const Text('Уведомления'),
                subtitle: const Text('Новые сообщения и звонки'),
              ),
              const SectionDivider(),
              SwitchListTile.adaptive(
                value: _messagePreview,
                onChanged: _notifications
                    ? (value) => setState(() => _messagePreview = value)
                    : null,
                secondary: _SettingsIcon(
                  icon: Icons.visibility_rounded,
                  color: context.tokens.accentSecondary,
                ),
                title: const Text('Текст в уведомлении'),
                subtitle: const Text('Показывать превью сообщения'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(label: 'Интерфейс'),
          SectionCard(
            children: [
              SwitchListTile.adaptive(
                value: _compactMode,
                onChanged: (value) => setState(() => _compactMode = value),
                secondary: _SettingsIcon(
                  icon: Icons.density_medium_rounded,
                  color: context.tokens.accentCyan,
                ),
                title: const Text('Компактные чаты'),
                subtitle: const Text('Эксперимент этапа 1'),
              ),
              const SectionDivider(),
              VibeListTile(
                icon: Icons.dark_mode_rounded,
                iconColor: context.tokens.accentPink,
                title: 'Тёмная тема',
                subtitle: 'Фирменная тема Вайба',
                trailing: Text(
                  'Всегда',
                  style: TextStyle(color: context.tokens.textSecondary),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          _SectionLabel(label: 'Безопасность и приложение'),
          SectionCard(
            children: [
              VibeListTile(
                icon: Icons.shield_rounded,
                iconColor: context.tokens.success,
                title: 'Конфиденциальность',
                subtitle: 'RLS и пользовательская сессия',
              ),
              const SectionDivider(),
              VibeListTile(
                icon: Icons.info_rounded,
                iconColor: context.tokens.warning,
                title: 'О приложении',
                subtitle: 'Вайб 0.1.0 · этап 1',
                trailing: SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: authState.isLoading ? null : _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.tokens.danger,
              side: BorderSide(color: context.tokens.danger),
            ),
            icon: authState.isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.tokens.danger,
                    ),
                  )
                : const Icon(Icons.logout_rounded),
            label: const Text('Выйти из аккаунта'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        0,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: context.tokens.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }
}
