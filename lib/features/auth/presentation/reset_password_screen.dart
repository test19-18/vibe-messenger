import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_message.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/router/route_locations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../core/widgets/backend_status_banner.dart';
import '../providers/auth_providers.dart';
import 'auth_scaffold.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final success = await ref
        .read(authControllerProvider(AuthAction.resetPassword).notifier)
        .resetPassword(_emailController.text);
    if (mounted && success) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(
      authControllerProvider(AuthAction.resetPassword),
    );
    final backend = ref.watch(backendBootstrapProvider);
    final enabled = backend.isReady && !authState.isLoading;
    final loginLocation = publicAuthLocation('/login', from: widget.from);

    if (_sent) {
      return AuthScaffold(
        title: 'Письмо отправлено',
        subtitle:
            'Откройте ссылку в письме для ${_emailController.text.trim()}, '
            'чтобы задать новый пароль.',
        showBack: true,
        backFallbackLocation: loginLocation,
        child: FilledButton(
          onPressed: () => context.go(loginLocation),
          child: const Text('Готово'),
        ),
      );
    }

    return AuthScaffold(
      title: 'Восстановить пароль',
      subtitle: 'Отправим безопасную ссылку на email вашего аккаунта.',
      showBack: true,
      backFallbackLocation: loginLocation,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackendStatusBanner(),
            if (!backend.isReady) const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              validator: Validators.email,
              onFieldSubmitted: enabled ? (_) => _submit() : null,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (authState.hasError) ...[
              Text(
                errorMessage(authState.error!),
                style: const TextStyle(color: AppColors.danger),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            FilledButton(
              onPressed: enabled ? _submit : null,
              child: authState.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Отправить ссылку'),
            ),
          ],
        ),
      ),
    );
  }
}
