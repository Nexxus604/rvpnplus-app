// First step of the R-VPN+ auth flow (TZ §5.2).
//
// User enters email → "Get code" calls POST /v1/auth/otp/request →
// navigates to OTP input page (driven by auth_notifier state).
//
// Layout: a full-width hero illustration (user-provided art, fading into
// the deep-space background) on top, the real email field + button + links
// below.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const OutlineInputBorder _noBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
  borderSide: BorderSide.none,
);

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
                      // Pulsing radiance over the orb the figure holds.
                      const Positioned.fill(
                        child: Align(
                          alignment: Alignment(0, -0.18),
                          child: _OrbGlow(),
                        ),
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
                        _ShimmerField(
                          child: TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enableSuggestions: false,
                            onSubmitted: (_) => submit(),
                            decoration: InputDecoration(
                              hintText: 'Email',
                              prefixIcon: const Icon(Icons.mail_outline_rounded),
                              filled: true,
                              fillColor: Cosmic.section,
                              // The shimmering ring is the border now.
                              border: _noBorder,
                              enabledBorder: _noBorder,
                              focusedBorder: _noBorder,
                            ),
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

/// Soft violet radiance that pulses (size + opacity) over the orb in the
/// hero art.
class _OrbGlow extends StatefulWidget {
  const _OrbGlow();
  @override
  State<_OrbGlow> createState() => _OrbGlowState();
}

class _OrbGlowState extends State<_OrbGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_c.value);
          final size = 150.0 + 70.0 * t;
          final op = 0.20 + 0.35 * t;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Cosmic.violetBright.withValues(alpha: op),
                  Cosmic.violet.withValues(alpha: op * 0.45),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Wraps a field with a shimmering (rotating sweep-gradient) border.
class _ShimmerField extends StatefulWidget {
  const _ShimmerField({required this.child});
  final Widget child;
  @override
  State<_ShimmerField> createState() => _ShimmerFieldState();
}

class _ShimmerFieldState extends State<_ShimmerField> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13.6),
            gradient: SweepGradient(
              transform: GradientRotation(_c.value * 2 * math.pi),
              colors: const [
                Cosmic.violet,
                Cosmic.violetBright,
                Color(0xFF49E0FF),
                Cosmic.violetBright,
                Cosmic.violet,
              ],
              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: widget.child,
      ),
    );
  }
}
