// App-wide floating AI assistant bubble. Mounted once in the MaterialApp
// builder Stack (app.dart) so it overlays every route. Hides itself unless
// the user is authenticated; tapping opens the full chat screen.

import 'package:flutter/material.dart';
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
        child: _Bubble(
          onTap: () {
            final ctx = rootNavKey.currentContext;
            if (ctx != null) GoRouter.of(ctx).push('/chat');
          },
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Cosmic.violet, Cosmic.violetBright],
            ),
            boxShadow: [
              BoxShadow(
                color: Cosmic.violet.withValues(alpha: .5),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
