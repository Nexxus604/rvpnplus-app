// First step of the R-VPN+ auth flow (TZ §5.2).
//
// User enters email → "Get code" calls POST /v1/auth/otp/request →
// navigates to OTP input page (driven by auth_notifier state).
//
// Layout: a full-width hero illustration (user-provided art, fading into
// the deep-space background) on top, the real email field + button + links
// below.

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
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
      backgroundColor: Cosmic.deepest,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero art, fading into the background at its bottom edge.
                  Stack(
                    children: [
                      Image.asset(
                        'assets/images/auth_hero.jpg',
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 72,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Cosmic.deepest],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Войдите по email',
                          style: theme.textTheme.titleMedium?.copyWith(color: Cosmic.text2),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => submit(),
                          decoration: const InputDecoration(
                            hintText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 8),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
