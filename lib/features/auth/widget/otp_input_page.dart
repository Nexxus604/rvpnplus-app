// OTP code entry for the R-VPN+ auth flow (TZ §5.2 step 7).
//
// 6 text fields auto-advance / auto-submit on completion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class OtpInputPage extends HookConsumerWidget {
  const OtpInputPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authNotifierProvider);

    if (auth is! AuthPendingOtp) {
      // Defensive: someone landed here without a pending OTP.
      // Router will redirect us back to /auth/email.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final controllers = List.generate(6, (_) => useTextEditingController());
    final focusNodes = List.generate(6, (_) => useFocusNode());
    final isSubmitting = useState(false);

    Future<void> submit(String code) async {
      isSubmitting.value = true;
      try {
        await ref.read(authNotifierProvider.notifier).verifyOtp(code);
        // Router will pick up the AuthAuthenticated state and navigate
        // us to /home — nothing to do here.
      } on AuthApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_localiseError(e))),
        );
        for (final c in controllers) {
          c.clear();
        }
        focusNodes.first.requestFocus();
      } finally {
        isSubmitting.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(authNotifierProvider.notifier).backToEmail(),
        ),
        title: const Text('Введите код'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Код отправлен',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Мы отправили 6-значный код на\n${auth.email}',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (i) {
                      return SizedBox(
                        width: 48,
                        child: TextField(
                          controller: controllers[i],
                          focusNode: focusNodes[i],
                          autofocus: i == 0,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            if (value.length == 1 && i < 5) {
                              focusNodes[i + 1].requestFocus();
                            } else if (value.isEmpty && i > 0) {
                              focusNodes[i - 1].requestFocus();
                            }
                            // Auto-submit once all 6 are filled.
                            final code = controllers.map((c) => c.text).join();
                            if (code.length == 6 && !isSubmitting.value) {
                              submit(code);
                            }
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  if (isSubmitting.value) const Center(child: CircularProgressIndicator()),
                  if (auth.lastError != null && !isSubmitting.value)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        auth.lastError!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: isSubmitting.value
                        ? null
                        : () {
                            ref
                                .read(authNotifierProvider.notifier)
                                .requestOtp(email: auth.email, purpose: auth.purpose);
                          },
                    child: const Text('Отправить код ещё раз'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _localiseError(AuthApiException e) {
    return switch (e.code) {
      AuthErrorCode.otpWrong => 'Неверный код. Попробуйте ещё раз.',
      AuthErrorCode.otpExpired => 'Код истёк. Запросите новый.',
      AuthErrorCode.otpExhausted => 'Слишком много попыток. Запросите новый код.',
      AuthErrorCode.otpCooldown => e.message, // «Подождите N сек…» с сервера
      AuthErrorCode.emailSendFailed => 'Не удалось отправить письмо. Попробуйте позже.',
      AuthErrorCode.refreshInvalid => 'Сессия истекла. Войдите заново.',
      AuthErrorCode.accountInactive => 'Аккаунт неактивен. Свяжитесь с поддержкой.',
      AuthErrorCode.network => 'Нет связи с сервером. Проверьте интернет.',
      AuthErrorCode.unknown => e.message,
    };
  }
}
