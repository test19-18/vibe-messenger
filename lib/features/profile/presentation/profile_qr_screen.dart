import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_tokens.dart';
import '../../../core/widgets/async_state_view.dart';
import '../domain/user_profile.dart';
import '../providers/profile_providers.dart';

class ProfileQrScreen extends ConsumerWidget {
  const ProfileQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(myProfileProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(ru: 'QR профиля', en: 'Profile QR')),
      ),
      body: AsyncStateView<UserProfile>(
        value: profileState,
        emptyTitle: context.tr(
          ru: 'Профиль не найден',
          en: 'Profile not found',
        ),
        emptyMessage: context.tr(
          ru: 'Не удалось сформировать QR.',
          en: 'Could not create a QR code.',
        ),
        onRetry: () => ref.invalidate(myProfileProvider),
        dataBuilder: (context, profile) {
          final uri = Uri(
            scheme: 'vibe',
            host: 'profile',
            pathSegments: [profile.id],
            queryParameters: profile.username == null
                ? null
                : {'username': profile.username},
          ).toString();
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    child: QrImageView(
                      data: uri,
                      version: QrVersions.auto,
                      size: 240,
                      backgroundColor: Colors.white,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: context.tokens.background,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: context.tokens.background,
                      ),
                      semanticsLabel: context.tr(
                        ru: 'QR-код профиля ${profile.visibleName}',
                        en: '${profile.visibleName} profile QR code',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    profile.visibleName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (profile.handle.isNotEmpty) Text(profile.handle),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: uri));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              context.tr(
                                ru: 'Ссылка профиля скопирована.',
                                en: 'Profile link copied.',
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(
                      context.tr(ru: 'Копировать ссылку', en: 'Copy link'),
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
