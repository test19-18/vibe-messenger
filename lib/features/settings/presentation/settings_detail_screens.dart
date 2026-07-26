import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/async_state_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../auth/providers/auth_providers.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../security/providers/app_lock_providers.dart';
import '../domain/app_preferences.dart';
import '../domain/user_device.dart';
import '../providers/device_providers.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    AppPreferences value,
  ) async {
    final success = await ref.read(appPreferencesProvider.notifier).save(value);
    if (!success && context.mounted) {
      final state = ref.read(appPreferencesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(state.error ?? Exception()))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).valueOrNull ?? const AppPreferences();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Оформление', en: 'Appearance')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(context.tr(ru: 'Тема', en: 'Theme')),
                trailing: DropdownButton<AppThemePreference>(
                  value: preferences.theme,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: AppThemePreference.system,
                      child: Text(context.tr(ru: 'Системная', en: 'System')),
                    ),
                    DropdownMenuItem(
                      value: AppThemePreference.light,
                      child: Text(context.tr(ru: 'Светлая', en: 'Light')),
                    ),
                    DropdownMenuItem(
                      value: AppThemePreference.dark,
                      child: Text(context.tr(ru: 'Тёмная', en: 'Dark')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _save(context, ref, preferences.copyWith(theme: value));
                    }
                  },
                ),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(context.tr(ru: 'Язык', en: 'Language')),
                subtitle: Text(
                  context.tr(
                    ru: 'Основная навигация и новые экраны',
                    en: 'Primary navigation and new screens',
                  ),
                ),
                trailing: DropdownButton<String>(
                  value: preferences.locale,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'ru', child: Text('Русский')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _save(context, ref, preferences.copyWith(locale: value));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            children: [
              ListTile(
                title: Text(context.tr(ru: 'Размер текста', en: 'Text size')),
                subtitle: Slider(
                  value: preferences.textScale,
                  min: 0.85,
                  max: 1.35,
                  divisions: 5,
                  label: '${(preferences.textScale * 100).round()}%',
                  onChanged: (value) => _save(
                    context,
                    ref,
                    preferences.copyWith(textScale: value),
                  ),
                ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                value: preferences.animationsEnabled,
                onChanged: (value) => _save(
                  context,
                  ref,
                  preferences.copyWith(animationsEnabled: value),
                ),
                title: Text(context.tr(ru: 'Анимации', en: 'Animations')),
                subtitle: Text(
                  context.tr(
                    ru: 'Отключение уменьшает движение интерфейса',
                    en: 'Disable to reduce interface motion',
                  ),
                ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                value: preferences.powerSaving,
                onChanged: (value) => _save(
                  context,
                  ref,
                  preferences.copyWith(powerSaving: value),
                ),
                title: Text(
                  context.tr(ru: 'Энергосбережение', en: 'Power saving'),
                ),
                subtitle: Text(
                  context.tr(
                    ru: 'Отключает анимации и тяжёлые эффекты',
                    en: 'Disables animations and heavy effects',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).valueOrNull ?? const AppPreferences();
    void save(AppPreferences value) {
      ref.read(appPreferencesProvider.notifier).save(value);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Конфиденциальность', en: 'Privacy')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SectionCard(
            children: [
              SwitchListTile.adaptive(
                value: preferences.sendReadReceipts,
                onChanged: (value) =>
                    save(preferences.copyWith(sendReadReceipts: value)),
                title: Text(
                  context.tr(ru: 'Отчёты о прочтении', en: 'Read receipts'),
                ),
                subtitle: Text(
                  context.tr(
                    ru: 'Также скрывает ваши маркеры от других',
                    en: 'Also hides your markers from others',
                  ),
                ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                value: preferences.showTypingStatus,
                onChanged: (value) =>
                    save(preferences.copyWith(showTypingStatus: value)),
                title: Text(
                  context.tr(ru: 'Статус «печатает»', en: 'Typing status'),
                ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                value: preferences.showLastSeen,
                onChanged: (value) =>
                    save(preferences.copyWith(showLastSeen: value)),
                title: Text(
                  context.tr(ru: 'Последняя активность', en: 'Last seen'),
                ),
                subtitle: Text(
                  context.tr(
                    ru: 'RLS применяет настройку к presence',
                    en: 'RLS applies this setting to presence',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).valueOrNull ?? const AppPreferences();
    final pushState = ref.watch(notificationsProvider);
    final userId = ref.watch(currentUserProvider)?.id;
    void save(AppPreferences value) {
      ref.read(appPreferencesProvider.notifier).save(value);
      // If push was toggled, update the notifications controller.
      if (value.pushEnabled != preferences.pushEnabled) {
        ref
            .read(notificationsProvider.notifier)
            .setPushEnabled(enabled: value.pushEnabled, userId: userId);
      }
    }

    final firebaseReady = pushState.firebaseReady;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Уведомления', en: 'Notifications')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Firebase status banner — honest state.
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: firebaseReady
                  ? context.tokens.success.withValues(alpha: 0.12)
                  : context.tokens.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: firebaseReady
                    ? context.tokens.success
                    : context.tokens.warning,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  firebaseReady
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: firebaseReady
                      ? context.tokens.success
                      : context.tokens.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firebaseReady
                            ? context.tr(
                                ru: 'Firebase подключён',
                                en: 'Firebase connected',
                              )
                            : context.tr(
                                ru: 'Firebase ожидает настройки',
                                en: 'Firebase pending setup',
                              ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        pushState.statusLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            children: [
              SwitchListTile.adaptive(
                value: preferences.pushEnabled,
                onChanged: firebaseReady
                    ? (value) => save(preferences.copyWith(pushEnabled: value))
                    : null,
                title: Text(
                  context.tr(ru: 'Push-уведомления', en: 'Push notifications'),
                ),
                subtitle: firebaseReady
                    ? null
                    : Text(
                        context.tr(
                          ru: 'Требует google-services.json',
                          en: 'Requires google-services.json',
                        ),
                      ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                value: preferences.pushMessagePreview,
                onChanged: preferences.pushEnabled && firebaseReady
                    ? (value) =>
                          save(preferences.copyWith(pushMessagePreview: value))
                    : null,
                title: Text(
                  context.tr(
                    ru: 'Показывать текст',
                    en: 'Show message preview',
                  ),
                ),
              ),
            ],
          ),
          if (firebaseReady) ...[
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              children: [
                ListTile(
                  leading: Icon(
                    pushState.notificationPermissionGranted
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_rounded,
                    color: pushState.notificationPermissionGranted
                        ? context.tokens.success
                        : context.tokens.warning,
                  ),
                  title: Text(
                    context.tr(
                      ru: 'Разрешение системы',
                      en: 'System permission',
                    ),
                  ),
                  subtitle: Text(
                    pushState.notificationPermissionGranted
                        ? context.tr(
                            ru: 'Уведомления разрешены',
                            en: 'Notifications permitted',
                          )
                        : context.tr(
                            ru: 'Нажмите, чтобы предоставить разрешение',
                            en: 'Tap to grant permission',
                          ),
                  ),
                  trailing: pushState.notificationPermissionGranted
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: context.tokens.success,
                        )
                      : FilledButton.tonal(
                          onPressed: () async {
                            final granted = await ref
                                .read(notificationsProvider.notifier)
                                .requestNotificationPermission();
                            if (!granted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.tr(
                                      ru:
                                          'Разрешение не предоставлено. '
                                          'Проверьте настройки системы.',
                                      en:
                                          'Permission not granted. '
                                          'Check system settings.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text(context.tr(ru: 'Разрешить', en: 'Allow')),
                        ),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.devices_rounded),
                  title: Text(
                    context.tr(
                      ru: 'Регистрация устройства',
                      en: 'Device registration',
                    ),
                  ),
                  subtitle: Text(
                    pushState.deviceRegistered
                        ? context.tr(
                            ru: 'Устройство зарегистрировано для push',
                            en: 'Device registered for push',
                          )
                        : pushState.fcmToken != null
                        ? context.tr(
                            ru: 'FCM token получен, регистрация…',
                            en: 'FCM token acquired, registering…',
                          )
                        : context.tr(
                            ru: 'FCM token не получен',
                            en: 'FCM token not acquired',
                          ),
                  ),
                  trailing: pushState.deviceRegistered
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: context.tokens.success,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class DataStorageSettingsScreen extends ConsumerWidget {
  const DataStorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(appPreferencesProvider).valueOrNull ?? const AppPreferences();
    void save(AppPreferences value) {
      ref.read(appPreferencesProvider.notifier).save(value);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Данные и память', en: 'Data and storage')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SectionCard(
            children: [
              SwitchListTile.adaptive(
                value: preferences.autoDownloadMedia,
                onChanged: (value) =>
                    save(preferences.copyWith(autoDownloadMedia: value)),
                title: Text(
                  context.tr(
                    ru: 'Автозагрузка медиа',
                    en: 'Media auto-download',
                  ),
                ),
                subtitle: Text(
                  context.tr(
                    ru: 'Политика сохранена; сетевые ограничения — следующий этап',
                    en: 'Preference is saved; network policies are a later step',
                  ),
                ),
              ),
              const Divider(indent: 16),
              SwitchListTile.adaptive(
                value: preferences.cacheMedia,
                onChanged: (value) =>
                    save(preferences.copyWith(cacheMedia: value)),
                title: Text(context.tr(ru: 'Кэш медиа', en: 'Media cache')),
                subtitle: Text(
                  context.tr(
                    ru: 'Локальный placeholder без офлайн-БД',
                    en: 'Local placeholder without an offline database',
                  ),
                ),
              ),
              const Divider(indent: 16),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(context.tr(ru: 'Очистить кэш', en: 'Clear cache')),
                subtitle: Text(
                  context.tr(
                    ru: 'Полноценный файловый cache index ещё не подключён',
                    en: 'A file cache index is not connected yet',
                  ),
                ),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.tr(
                        ru: 'Локальный кэш пока не создаётся.',
                        en: 'No local cache is currently created.',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final first = TextEditingController();
    final second = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(ru: 'Установить PIN', en: 'Set PIN')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: first,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: context.tr(
                  ru: 'PIN (4–8 цифр)',
                  en: 'PIN (4–8 digits)',
                ),
              ),
            ),
            TextField(
              controller: second,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: context.tr(ru: 'Повторите PIN', en: 'Repeat PIN'),
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
            child: Text(context.tr(ru: 'Сохранить', en: 'Save')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      first.dispose();
      second.dispose();
      return;
    }
    try {
      if (first.text != second.text) {
        throw const FormatException('PIN-коды не совпадают.');
      }
      await ref.read(appLockProvider.notifier).setPin(first.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr(ru: 'PIN сохранён.', en: 'PIN saved.')),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    } finally {
      first.dispose();
      second.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    final configuration = state.valueOrNull?.configuration;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'Блокировка приложения', en: 'App lock')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text(
                  configuration?.pinEnabled == true
                      ? context.tr(ru: 'Изменить PIN', en: 'Change PIN')
                      : context.tr(ru: 'Установить PIN', en: 'Set PIN'),
                ),
                onTap: () => _setPin(context, ref),
              ),
              const Divider(indent: 56),
              SwitchListTile.adaptive(
                value: configuration?.biometricEnabled ?? false,
                onChanged: state.isLoading
                    ? null
                    : (value) async {
                        try {
                          await ref
                              .read(appLockProvider.notifier)
                              .setBiometricEnabled(value);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(errorMessage(error))),
                            );
                          }
                        }
                      },
                title: Text(context.tr(ru: 'Биометрия', en: 'Biometrics')),
                subtitle: Text(
                  context.tr(
                    ru: 'Требует нативной настройки local_auth',
                    en: 'Requires native local_auth setup',
                  ),
                ),
              ),
            ],
          ),
          if (configuration?.enabled == true) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => ref.read(appLockProvider.notifier).disable(),
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(
                context.tr(ru: 'Отключить блокировку', en: 'Disable app lock'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(ru: 'Устройства и сессии', en: 'Devices and sessions'),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(
              context.tr(
                ru: 'Текущая Supabase-сессия: ${user?.email ?? 'неизвестно'}. Клиент не может перечислять или отзывать другие Auth-сессии; ниже показаны зарегистрированные push-устройства.',
                en: 'Current Supabase session: ${user?.email ?? 'unknown'}. The client cannot list or revoke other Auth sessions; registered push devices are shown below.',
              ),
            ),
          ),
          Expanded(
            child: AsyncStateView<List<UserDevice>>(
              value: devices,
              isEmpty: (items) => items.isEmpty,
              emptyTitle: context.tr(
                ru: 'Устройств пока нет',
                en: 'No devices yet',
              ),
              emptyMessage: context.tr(
                ru: 'FCM token появится после подключения Firebase SDK.',
                en: 'An FCM token will appear after Firebase SDK is connected.',
              ),
              onRetry: () => ref.invalidate(devicesProvider),
              dataBuilder: (context, items) => ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) =>
                    _DeviceTile(device: items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});

  final UserDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: Icon(
          device.platform == 'android'
              ? Icons.android_rounded
              : Icons.devices_other_rounded,
        ),
        title: Text(device.deviceName ?? device.platform),
        subtitle: Text(
          '${device.isActive ? context.tr(ru: 'активно', en: 'active') : context.tr(ru: 'отключено', en: 'disabled')} · '
          '${DateFormat('dd.MM.yyyy HH:mm').format(device.lastSeenAt)}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'disable') {
              ref.read(deviceMutationProvider.notifier).disable(device.id);
            } else if (value == 'remove') {
              ref.read(deviceMutationProvider.notifier).remove(device.id);
            }
          },
          itemBuilder: (context) => [
            if (device.isActive)
              PopupMenuItem(
                value: 'disable',
                child: Text(context.tr(ru: 'Отключить', en: 'Disable')),
              ),
            PopupMenuItem(
              value: 'remove',
              child: Text(context.tr(ru: 'Удалить', en: 'Remove')),
            ),
          ],
        ),
      ),
    );
  }
}
