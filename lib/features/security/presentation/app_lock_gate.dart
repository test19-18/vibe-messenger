import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/app_lock_providers.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final _pinController = TextEditingController();
  bool _wasBackgrounded = false;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      ref.read(appLockProvider.notifier).lock();
    }
  }

  Future<void> _unlockWithPin() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final success = await ref
        .read(appLockProvider.notifier)
        .unlockWithPin(_pinController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _error = success
          ? null
          : context.tr(ru: 'Неверный PIN.', en: 'Incorrect PIN.');
    });
    if (success) {
      _pinController.clear();
    }
  }

  Future<void> _unlockWithBiometric() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final success = await ref
        .read(appLockProvider.notifier)
        .unlockWithBiometric();
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      _error = success
          ? null
          : context.tr(
              ru: 'Не удалось подтвердить биометрию.',
              en: 'Biometric authentication failed.',
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockProvider);
    final current = lockState.valueOrNull;
    if (current == null || !current.locked) {
      return widget.child;
    }

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 58,
                      color: AppColors.electricBlue,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      context.tr(ru: 'Вайб заблокирован', en: 'Vibe is locked'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.tr(
                        ru: 'Подтвердите, что это вы.',
                        en: 'Confirm that it is you.',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (current.configuration.pinEnabled) ...[
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        key: const Key('app_lock_pin_field'),
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        maxLength: 8,
                        onSubmitted: _checking ? null : (_) => _unlockWithPin(),
                        decoration: InputDecoration(
                          labelText: context.tr(ru: 'PIN-код', en: 'PIN'),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: _checking ? null : _unlockWithPin,
                        child: Text(
                          context.tr(ru: 'Разблокировать', en: 'Unlock'),
                        ),
                      ),
                    ],
                    if (current.configuration.biometricEnabled) ...[
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _checking ? null : _unlockWithBiometric,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: Text(
                          context.tr(
                            ru: 'Использовать биометрию',
                            en: 'Use biometrics',
                          ),
                        ),
                      ),
                    ],
                    if (_checking) ...[
                      const SizedBox(height: AppSpacing.md),
                      const CircularProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
