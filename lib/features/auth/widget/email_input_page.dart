// First step of the R-VPN+ auth flow (TZ §5.2).
//
// User enters email → "Get code" calls POST /v1/auth/otp/request →
// navigates to OTP input page (driven by auth_notifier state).
//
// Layout: the hero artwork fills the whole screen (BoxFit.cover — the art is
// drawn wide on purpose so the centre survives any aspect ratio). The form
// (email + button + links) is anchored to the bottom over a dark scrim, and
// lifts above the keyboard when it opens.

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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
      // Keep the background full-bleed when the keyboard opens; we lift the
      // form ourselves via the bottom inset below.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full-screen hero. Drawn wide on purpose: cover keeps the centre
          // (figure + orb) on any phone/tablet aspect ratio.
          Positioned.fill(
            child: Image.asset(
              'assets/images/auth_hero.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          // Pulsing radiance over the orb (approx centre).
          const Positioned.fill(
            child: Align(
              alignment: Alignment(0, -0.12),
              child: _OrbGlow(),
            ),
          ),
          // Dark scrim toward the bottom so the form stays legible.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.transparent, Cosmic.deepest],
                  stops: [0.0, 0.42, 0.9],
                ),
              ),
            ),
          ),
          // Form, anchored to the bottom, lifting above the keyboard.
          SafeArea(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                  const Spacer(),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Войдите по email',
                              style: theme.textTheme.titleMedium?.copyWith(color: Cosmic.text2),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            _ShimmerField(
                              child: TextField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) => submit(),
                                decoration: const InputDecoration(
                                  hintText: 'Email',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                  filled: true,
                                  fillColor: Cosmic.section,
                                  border: _noBorder,
                                  enabledBorder: _noBorder,
                                  focusedBorder: _noBorder,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
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
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () {
                                // TODO(phase1): /auth/telegram bind flow (TZ §5.4).
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
                ],
              ),
            ),
          ),
        ],
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
