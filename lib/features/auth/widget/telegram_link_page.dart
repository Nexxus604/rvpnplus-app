// In-app "link my Telegram" flow (TZ §5.4):
//   start() → open @rvpnplus_bot deeplink → user enters email+OTP in the bot
//   → we poll status() → on "ready" we log in with the returned tokens
//   (the account is now bound to their Telegram, so their subscription &
//   servers appear). The router redirects to /home once authenticated.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/core/api/tg_link_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Phase { starting, waiting, expired, error }

class TelegramLinkPage extends ConsumerStatefulWidget {
  const TelegramLinkPage({super.key});

  @override
  ConsumerState<TelegramLinkPage> createState() => _TelegramLinkPageState();
}

class _TelegramLinkPageState extends ConsumerState<TelegramLinkPage> {
  _Phase _phase = _Phase.starting;
  String? _requestId;
  String? _deeplink;
  Timer? _poll;
  DateTime? _deadline;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.starting);
    try {
      final res = await ref.read(tgLinkApiProvider).start();
      if (!mounted) return;
      _requestId = res.requestId;
      _deeplink = res.botDeeplink;
      _deadline = DateTime.now().add(Duration(seconds: res.expiresIn));
      setState(() => _phase = _Phase.waiting);
      await _openBot();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  Future<void> _openBot() async {
    final link = _deeplink;
    if (link == null) return;
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && _requestId != null) {
      // Fallback to the https t.me link if the tg:// scheme didn't resolve.
      final https = Uri.parse('https://t.me/rvpnplus_bot?start=link_${_requestId!}');
      try {
        await launchUrl(https, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  Future<void> _check() async {
    if (_checking || _requestId == null) return;
    if (_deadline != null && DateTime.now().isAfter(_deadline!)) {
      _poll?.cancel();
      if (mounted) setState(() => _phase = _Phase.expired);
      return;
    }
    _checking = true;
    try {
      final st = await ref.read(tgLinkApiProvider).status(_requestId!);
      if (!mounted) return;
      if (st.isReady && st.accessToken != null && st.refreshToken != null) {
        _poll?.cancel();
        final ok = await ref.read(authNotifierProvider.notifier).loginWithTokens(
              accessToken: st.accessToken!,
              refreshToken: st.refreshToken!,
            );
        // On success the router redirect (auth state → authenticated) takes
        // us to /home automatically. On failure, surface an error.
        if (!ok && mounted) setState(() => _phase = _Phase.error);
      } else if (st.isExpired) {
        _poll?.cancel();
        if (mounted) setState(() => _phase = _Phase.expired);
      }
    } catch (_) {
      // Transient network error — keep polling.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Привязка Telegram')),
      body: CosmicBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded, size: 56, color: Cosmic.violetBright),
                  const SizedBox(height: 20),
                  Text(_title(), textAlign: TextAlign.center,
                      style: const TextStyle(color: Cosmic.text, fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text(_subtitle(), textAlign: TextAlign.center,
                      style: const TextStyle(color: Cosmic.text2, fontSize: 14, height: 1.4)),
                  const SizedBox(height: 24),
                  ..._actions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _title() => switch (_phase) {
        _Phase.starting => 'Открываем Telegram…',
        _Phase.waiting => 'Подтвердите в Telegram',
        _Phase.expired => 'Время вышло',
        _Phase.error => 'Не удалось привязать',
      };

  String _subtitle() => switch (_phase) {
        _Phase.starting => 'Готовим запрос…',
        _Phase.waiting =>
          'В боте @rvpnplus_bot введите ваш email и код из письма. '
              'Как только подтвердите — приложение войдёт автоматически.',
        _Phase.expired => 'Запрос на привязку истёк. Попробуйте ещё раз.',
        _Phase.error => 'Что-то пошло не так. Попробуйте ещё раз.',
      };

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.starting:
        return const [CircularProgressIndicator()];
      case _Phase.waiting:
        return [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openBot,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Открыть Telegram снова'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Отмена'),
          ),
        ];
      case _Phase.expired:
      case _Phase.error:
        return [
          FilledButton(onPressed: _start, child: const Text('Повторить')),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Назад'),
          ),
        ];
    }
  }
}
