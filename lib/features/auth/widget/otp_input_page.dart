// OTP code entry for the R-VPN+ auth flow (TZ §5.2 step 7).
//
// Built on `pinput`, which handles the fiddly bits a hand-rolled
// 6-TextField version got wrong:
//   - backspace from the last filled cell actually deletes (the old
//     version ignored it when the cursor sat on the final digit);
//   - auto-submit fires via onCompleted the moment all 6 digits are in,
//     no separate button press;
//   - wrong code → cells flash red (errorPinTheme) AND the whole field
//     shakes, then clears for another attempt.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pinput/pinput.dart';

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

    final pinController = useTextEditingController();
    final pinFocus = useFocusNode();
    final isSubmitting = useState(false);
    final hasError = useState(false);

    // Shake animation for the wrong-code feedback.
    final shakeController = useAnimationController(
      duration: const Duration(milliseconds: 450),
    );

    Future<void> submit(String code) async {
      if (isSubmitting.value) return;
      isSubmitting.value = true;
      hasError.value = false;
      try {
        await ref.read(authNotifierProvider.notifier).verifyOtp(code);
        // Success → router picks up AuthAuthenticated and navigates to
        // /home. Nothing to do here.
      } on AuthApiException catch (e) {
        if (!context.mounted) return;
        // Turn the cells red and shake. The red STAYS until the user
        // edits the field (handled in onChanged), instead of clearing
        // on a short timer — the timer version flashed too fast to see
        // and sometimes never rendered at all.
        hasError.value = true;
        shakeController.forward(from: 0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_localiseError(e))),
        );
      } finally {
        isSubmitting.value = false;
      }
    }

    const cellWidth = 46.0;
    const cellHeight = 56.0;
    final defaultPinTheme = PinTheme(
      width: cellWidth,
      height: cellHeight,
      textStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
      ),
    );
    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: theme.colorScheme.primary, width: 2),
    );
    final errorPinTheme = PinTheme(
      width: cellWidth,
      height: cellHeight,
      textStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.error,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.error, width: 2),
        color: theme.colorScheme.error.withValues(alpha: 0.12),
      ),
    );

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
                  AnimatedBuilder(
                    animation: shakeController,
                    builder: (context, child) {
                      // Damped sine shake: a few horizontal oscillations
                      // that decay to zero over the animation.
                      final t = shakeController.value;
                      final dx = (t == 0 || t == 1)
                          ? 0.0
                          : 12.0 * (1 - t) * math.sin(t * 3 * 2 * math.pi);
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    child: Pinput(
                      length: 6,
                      controller: pinController,
                      focusNode: pinFocus,
                      autofocus: true,
                      defaultPinTheme: defaultPinTheme,
                      focusedPinTheme: focusedPinTheme,
                      errorPinTheme: errorPinTheme,
                      forceErrorState: hasError.value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      closeKeyboardWhenCompleted: true,
                      // Auto-submit the instant all six digits are entered.
                      onCompleted: submit,
                      // Clear the red error state as soon as the user
                      // edits (backspaces) after a wrong code.
                      onChanged: (_) {
                        if (hasError.value) hasError.value = false;
                      },
                      enabled: !isSubmitting.value,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (isSubmitting.value)
                    const Center(child: CircularProgressIndicator()),
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
