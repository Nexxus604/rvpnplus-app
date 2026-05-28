// Stage 2 — server catalog / management. Lists every activatable server
// (from /v1/subscription/catalog) with a switch: ON provisions it for the
// account (POST /subscription/servers), OFF deprovisions it (DELETE
// /subscription/servers/{slot_id}). Both mirror into the Telegram bot.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/api/subscription_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ServerCatalogPage extends ConsumerStatefulWidget {
  const ServerCatalogPage({super.key});

  @override
  ConsumerState<ServerCatalogPage> createState() => _ServerCatalogPageState();
}

class _ServerCatalogPageState extends ConsumerState<ServerCatalogPage> {
  late Future<CatalogResult> _future;
  // Server codes with an in-flight activate/deactivate call.
  final Set<String> _pending = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<CatalogResult> _load() {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      throw const SubscriptionApiException(
          SubscriptionErrorCode.unauthorized, 'Not logged in');
    }
    return ref.read(subscriptionApiProvider).catalog(accessToken: auth.accessToken);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _toggle(CatalogServer s) async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated || _pending.contains(s.code)) return;
    final api = ref.read(subscriptionApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    final activating = !s.isActivated;

    if (!activating) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Отключить сервер?'),
          content: Text('«${s.city ?? s.name}» будет удалён из подписки — и здесь, и в боте.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Отключить'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _pending.add(s.code));
    messenger.showSnackBar(SnackBar(
      content: Text(activating
          ? 'Активирую ${s.city ?? s.code}… это может занять до минуты'
          : 'Отключаю ${s.city ?? s.code}…'),
      duration: const Duration(seconds: 8),
    ));
    try {
      if (activating) {
        await api.activateServer(accessToken: auth.accessToken, serverCode: s.code);
      } else {
        await api.deleteServer(accessToken: auth.accessToken, slotId: s.slotId!);
      }
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(activating
            ? '«${s.city ?? s.code}» активирован'
            : '«${s.city ?? s.code}» отключён'),
      ));
      _reload();
    } on SubscriptionApiException catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      final msg = switch (e.code) {
        SubscriptionErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
        SubscriptionErrorCode.network => 'Нет связи с сервером.',
        SubscriptionErrorCode.unknown => e.message,
      };
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _pending.remove(s.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Серверы'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: CosmicBackground(
        child: SafeArea(
          child: FutureBuilder<CatalogResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorView(error: snapshot.error!, onRetry: _reload);
              }
              final result = snapshot.data!;
              if (result.subscription == null) {
                return const _NoSubView();
              }
              final servers = result.servers;
              // Group by country, preserving the server order (foreign→RU).
              final order = <String>[];
              final groups = <String, List<CatalogServer>>{};
              for (final s in servers) {
                if (!groups.containsKey(s.countryCode)) order.add(s.countryCode);
                groups.putIfAbsent(s.countryCode, () => []).add(s);
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    const _Hint(),
                    const Gap(8),
                    for (final cc in order) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Row(
                          children: [
                            Text(groups[cc]!.first.countryFlag,
                                style: const TextStyle(fontSize: 20)),
                            const Gap(8),
                            Text(groups[cc]!.first.countryName,
                                style: const TextStyle(
                                    color: Cosmic.text2,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      for (final s in groups[cc]!)
                        _ServerRow(
                          server: s,
                          pending: _pending.contains(s.code),
                          onToggle: () => _toggle(s),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.server, required this.pending, required this.onToggle});
  final CatalogServer server;
  final bool pending;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: server.isActivated
              ? Cosmic.violet.withValues(alpha: .5)
              : Colors.white.withValues(alpha: .06),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        server.city ?? server.name,
                        style: const TextStyle(
                            color: Cosmic.text, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (server.isPremium) ...[
                      const Gap(6),
                      const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFC857)),
                    ],
                  ],
                ),
                const Gap(2),
                Text('Нагрузка ~${server.loadPercent}%',
                    style: const TextStyle(color: Cosmic.text2, fontSize: 12)),
              ],
            ),
          ),
          if (pending)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Switch(value: server.isActivated, onChanged: (_) => onToggle()),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) {
    return const Text(
      'Включите серверы, которые хотите использовать. Активация занимает несколько '
      'секунд (создаём доступ на ноде). Изменения применяются и в Telegram-боте.',
      style: TextStyle(color: Cosmic.muted, fontSize: 12, height: 1.4),
    );
  }
}

class _NoSubView extends StatelessWidget {
  const _NoSubView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'У вас нет активной подписки.\nАктивируйте её, чтобы добавлять серверы.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Cosmic.text2, height: 1.4),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is SubscriptionApiException
        ? switch ((error as SubscriptionApiException).code) {
            SubscriptionErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
            SubscriptionErrorCode.network => 'Нет связи с сервером.',
            SubscriptionErrorCode.unknown => (error as SubscriptionApiException).message,
          }
        : 'Что-то пошло не так';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 44, color: Cosmic.text2),
          const Gap(14),
          Text(msg, style: const TextStyle(color: Cosmic.text2)),
          const Gap(14),
          FilledButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
