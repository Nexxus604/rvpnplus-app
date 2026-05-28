// App-wide floating AI assistant bubble. Mounted once in the MaterialApp
// builder Stack (app.dart) so it overlays every route. Hides itself unless
// the user is authenticated; tapping opens the full chat screen.
//
// Rocket mark = FontAwesomeIcons.rocket on a violet disc with a clean
// expanding ripple pulse — the chat.rvpn.space launcher style.

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChatBubble extends ConsumerWidget {
  const ChatBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authNotifierProvider) is AuthAuthenticated;
    if (!authed) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: 96,
      child: SafeArea(
        child: RocketMark(
          onTap: () {
            final ctx = rootNavKey.currentContext;
            if (ctx != null) GoRouter.of(ctx).push('/chat');
          },
        ),
      ),
    );
  }
}

/// Violet rocket disc with a clean expanding ripple pulse (chat.rvpn.space
/// launcher style). Used for the support button (with [onTap]) and, statically,
/// as the chat avatar ([pulse] off).
class RocketMark extends StatefulWidget {
  const RocketMark({super.key, this.size = 60, this.onTap, this.pulse = true});

  final double size;
  final VoidCallback? onTap;
  final bool pulse;

  @override
  State<RocketMark> createState() => _RocketMarkState();
}

class _RocketMarkState extends State<RocketMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _ripple.repeat();
  }

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  // One expanding+fading ring (a ripple emanating from the disc).
  Widget _ring(double t) {
    return Transform.scale(
      scale: 1.0 + 0.5 * t,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Cosmic.violetBright.withValues(alpha: 0.40 * (1 - t)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disc = AnimatedBuilder(
      animation: _ripple,
      builder: (context, child) {
        final t = _ripple.value;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (widget.pulse) ...[
                _ring(t),
                _ring((t + 0.5) % 1.0),
              ],
              child!,
            ],
          ),
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Cosmic.violet, Cosmic.violetBright],
          ),
          boxShadow: [
            BoxShadow(
              color: Cosmic.violet.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.rocket,
            color: Colors.white,
            size: widget.size * 0.42,
          ),
        ),
      ),
    );

    if (widget.onTap == null) return disc;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: disc,
    );
  }
}
