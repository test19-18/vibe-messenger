import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/backend_status_banner.dart';
import '../../../core/widgets/section_card.dart';
import '../../auth/providers/auth_providers.dart';

class SettingsHubScreen extends ConsumerWidget {
  const SettingsHubScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Выйти из аккаунта?', en: 'Sign out?')),
        content: Text(
          context.tr(
            ru: 'Локальная Supabase-сессия будет удалена с устройства.',
            en: 'The local Supabase session will be removed from this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr(ru: 'Отмена', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.tr(ru: 'Выйти', en: 'Sign out'),
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(authControllerProvider(AuthAction.signOut).notifier)
          .signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signOutState = ref.watch(authControllerProvider(AuthAction.signOut));
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
      appBar: AppBar(
        title: Text(context.tr(ru: 'Настройки', en: 'Settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          110,
        ),
        children: [
          const BackendStatusBanner(),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            children: [
              VibeListTile(
                icon: Icons.notifications_rounded,
                iconColor: AppColors.electricBlue,
                title: context.tr(ru: 'Уведомления', en: 'Notifications'),
                subtitle: context.tr(
                  ru: 'Push, каналы, разрешение',
                  en: 'Push, channels, permission',
                ),
                onTap: () => context.push('/settings/notifications'),
              ),
              const Divider(indent: 70),
              VibeListTile(
                icon: Icons.lock_person_rounded,
                iconColor: AppColors.success,
                title: context.tr(ru: 'Конфиденциальность', en: 'Privacy'),
                subtitle: context.tr(
                  ru: 'Presence, typing и read receipts',
                  en: 'Presence, typing and read receipts',
                ),
                onTap: () => context.push('/settings/privacy'),
              ),
              const Divider(indent: 70),
              VibeListTile(
                icon: Icons.palette_rounded,
                iconColor: AppColors.pink,
                title: context.tr(ru: 'Оформление', en: 'Appearance'),
                subtitle: context.tr(
                  ru: 'Тема, RU/EN, текст и анимации',
                  en: 'Theme, RU/EN, text and animations',
                ),
                onTap: () => context.push('/settings/appearance'),
              ),
              const Divider(indent: 70),
              VibeListTile(
                icon: Icons.storage_rounded,
                iconColor: AppColors.cyan,
                title: context.tr(
                  ru: 'Данные и память',
                  en: 'Data and storage',
                ),
                subtitle: context.tr(
                  ru: 'Автозагрузка и cache placeholders',
                  en: 'Auto-download and cache placeholders',
                ),
                onTap: () => context.push('/settings/data'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            children: [
              VibeListTile(
                icon: Icons.phone_in_talk_rounded,
                iconColor: AppColors.success,
                title: context.tr(ru: 'Звонки', en: 'Calls'),
                subtitle: context.tr(
                  ru: 'История аудио/видеозвонков',
                  en: 'Audio/video call history',
                ),
                onTap: () => context.push('/call-history'),
              ),
              const Divider(indent: 70),
              VibeListTile(
                icon: Icons.phonelink_lock_rounded,
                iconColor: AppColors.purple,
                title: context.tr(ru: 'Блокировка приложения', en: 'App lock'),
                subtitle: context.tr(
                  ru: 'Локальный PIN и биометрия',
                  en: 'Local PIN and biometrics',
                ),
                onTap: () => context.push('/settings/lock'),
              ),
              const Divider(indent: 70),
              VibeListTile(
                icon: Icons.devices_rounded,
                iconColor: AppColors.warning,
                title: context.tr(
                  ru: 'Устройства и сессии',
                  en: 'Devices and sessions',
                ),
                subtitle: context.tr(
                  ru: 'user_devices и текущая Auth-сессия',
                  en: 'user_devices and current Auth session',
                ),
                onTap: () => context.push('/settings/devices'),
              ),
              const Divider(indent: 70),
              VibeListTile(
                icon: Icons.group_add_rounded,
                iconColor: AppColors.electricBlue,
                title: context.tr(ru: 'Вступить в группу', en: 'Join a group'),
                subtitle: context.tr(
                  ru: 'Приглашения, token и заявки',
                  en: 'Invitations, token and requests',
                ),
                onTap: () => context.push('/group-access'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const SectionCard(
            children: [
              VibeListTile(
                icon: Icons.info_rounded,
                iconColor: AppColors.textSecondary,
                title: 'Вайб 0.2.0',
                subtitle: 'Flutter + Supabase · без service-role/Firebase SDK',
                trailing: SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: signOutState.isLoading
                ? null
                : () => _signOut(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: signOutState.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
            label: Text(context.tr(ru: 'Выйти из аккаунта', en: 'Sign out')),
          ),
        ],
      ),
    );
  }
}
