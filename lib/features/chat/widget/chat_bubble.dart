// App-wide floating AI assistant bubble. Mounted once in the MaterialApp
// builder Stack (app.dart) so it overlays every route. Hides itself unless
// the user is authenticated; tapping opens the full chat screen.
//
// Rocket mark = FontAwesomeIcons.rocket (same rocket motif as rocketvpn.net),
// on a violet gradient disc with a pulsing magenta halo.

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

/// Violet rocket disc with a pulsing magenta halo. Used for the floating
/// bubble (with [onTap]) and, statically, as the chat avatar.
class RocketMark extends StatefulWidget {
  const RocketMark({super.key, this.size = 60, this.onTap, this.pulse = true});

  final double size;
  final VoidCallback? onTap;
  final bool pulse;

  @override
  State<RocketMark> createState() => _RocketMarkState();
}

class _RocketMarkState extends State<RocketMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  static const _halo = Color(0xFFC04AE8); // magenta-pink glow

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disc = AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = widget.pulse ? _c.value : 0.0;
        final glow = 14.0 + 12.0 * t; // halo grows/shrinks
        final scale = 1.0 + 0.05 * t;
        return Transform.scale(
          scale: scale,
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
                  color: _halo.withValues(alpha: 0.45 + 0.25 * t),
                  blurRadius: glow,
                  spreadRadius: 1.5 + 1.5 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Center(
        child: FaIcon(
          FontAwesomeIcons.rocket,
          color: Colors.white,
          size: widget.size * 0.42,
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
