// First step of the R-VPN+ auth flow (TZ §5.2).
//
// User enters email → "Get code" calls POST /v1/auth/otp/request →
// navigates to OTP input page (driven by auth_notifier state).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EmailInputPage extends HookConsumerWidget {
  const EmailInputPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final emailController = useTextEditingController();
    final isSubmitting = useState(false);

    Future<void> submit() async {
      final email = emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите корректный email')),
        );
        return;
      }
      isSubmitting.value = true;
      try {
        await ref.read(authNotifierProvider.notifier).requestOtp(email: email);
        // Router will pick up the AuthPendingOtp state and navigate to
        // /auth/otp — nothing else to do.
      } on AuthApiException catch (e) {
        if (!context.mounted) return;
        final msg = switch (e.code) {
          AuthErrorCode.emailSendFailed =>
            'Не удалось отправить письмо. Проверьте, что email написан верно.',
          AuthErrorCode.otpCooldown => e.message, // «Подождите N сек…» с сервера
          AuthErrorCode.network => 'Нет связи с сервером. Проверьте интернет.',
          _ => e.message,
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } finally {
        isSubmitting.value = false;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CosmicBackground(
        child: SafeArea(
          child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _LogoMark(),
                  const SizedBox(height: 20),
                  Text(
                    'R-VPN+',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Войдите по email',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofocus: true,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isSubmitting.value ? null : submit,
                    child: isSubmitting.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Получить код'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      // TODO(phase1): navigate to /auth/telegram for
                      // existing bot-user binding flow (TZ §5.4).
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Скоро — привязка Telegram-аккаунта'),
                        ),
                      );
                    },
                    child: const Text('У меня уже есть Telegram-аккаунт'),
                  ),
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

class _LogoMark extends StatelessWidget {
  const _LogoMark();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Cosmic.violet, Cosmic.violetBright],
          ),
          boxShadow: [
            BoxShadow(
              color: Cosmic.violet.withValues(alpha: .55),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 52),
      ),
    );
  }
}
