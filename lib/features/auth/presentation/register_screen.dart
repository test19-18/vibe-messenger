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

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _emailConfirmationSent = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final from = validatedInternalRedirect(widget.from);
    final response = await ref
        .read(authControllerProvider(AuthAction.signUp).notifier)
        .signUp(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text,
        );
    if (!mounted || response == null) {
      return;
    }
    if (response.session != null) {
      context.go(from ?? '/chats');
      return;
    }
    setState(() => _emailConfirmationSent = true);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider(AuthAction.signUp));
    final backend = ref.watch(backendBootstrapProvider);
    final enabled = backend.isReady && !authState.isLoading;
    final loginLocation = publicAuthLocation('/login', from: widget.from);

    if (_emailConfirmationSent) {
      return AuthScaffold(
        title: 'Проверьте почту',
        subtitle:
            'Мы отправили ссылку подтверждения на ${_emailController.text.trim()}.',
        showBack: true,
        backFallbackLocation: loginLocation,
        child: FilledButton.icon(
          onPressed: () => context.go(loginLocation),
          icon: const Icon(Icons.mark_email_read_rounded),
          label: const Text('Вернуться ко входу'),
        ),
      );
    }

    return AuthScaffold(
      title: 'Создать аккаунт',
      subtitle:
          'Имя, email и надёжный пароль — остальное можно заполнить позже.',
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
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              validator: Validators.displayName,
              decoration: const InputDecoration(
                labelText: 'Имя',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.newUsername],
              validator: Validators.email,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.password,
              onFieldSubmitted: enabled ? (_) => _submit() : null,
              decoration: InputDecoration(
                labelText: 'Пароль',
                helperText: 'Минимум 8 символов',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
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
                  : const Text('Продолжить'),
            ),
          ],
        ),
      ),
    );
  }
}
