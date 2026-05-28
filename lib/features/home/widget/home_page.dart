// R-VPN+ cosmic home: the connect button on top, the account's real servers
// (synced with the Telegram bot) listed below. Starfield backdrop. Servers are
// fetched from /v1/subscription/servers and kept in sync with Hiddify profiles
// (see ServerProfileSync); tapping connects, the trash icon deletes both here
// and in the bot.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/api/subscription_api.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/servers/notifier/server_visibility.dart';
import 'package:hiddify/features/servers/widget/ping_label.dart';
import 'package:hiddify/features/servers/widget/server_profile_sync.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Assets.images.logo.svg(height: 24),
            const Gap(8),
            Text(t.common.appTitle),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Серверы',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => GoRouter.of(context).push('/servers/catalog'),
          ),
          IconButton(
            tooltip: 'Маршрутизация',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () =>
                ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings(),
          ),
          IconButton(
            tooltip: 'Добавить профиль',
            icon: const Icon(Icons.add_rounded),
            onPressed: () =>
                ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
          ),
          IconButton(
            tooltip: 'Аккаунт',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => GoRouter.of(context).push('/account'),
          ),
          const Gap(4),
        ],
      ),
      body: const CosmicBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(top: 8, bottom: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: 220, child: Center(child: ConnectionButton())),
                    ActiveProxyDelayIndicator(),
                  ],
                ),
              ),
              Gap(8),
              Expanded(child: _MyServersSection()),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyServersSection extends ConsumerStatefulWidget {
  const _MyServersSection();
  @override
  ConsumerState<_MyServersSection> createState() => _MyServersSectionState();
}

class _MyServersSectionState extends ConsumerState<_MyServersSection> {
  late Future<MyServersResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MyServersResult> _load() async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      throw const SubscriptionApiException(
          SubscriptionErrorCode.unauthorized, 'Not logged in');
    }
    final result =
        await ref.read(subscriptionApiProvider).myServers(accessToken: auth.accessToken);
    final currentUrls =
        result.servers.map((s) => s.configUrl).whereType<String>().toSet();
    // The list is authoritative only with an active subscription and at least
    // one server every entry of which has a config_url — otherwise a transient
    // partial response must not delete our own working profiles.
    final authoritative = result.subscription != null &&
        result.servers.isNotEmpty &&
        result.servers.every((s) => s.configUrl != null);
    await ref
        .read(serverProfileSyncProvider)
        .reconcile(currentUrls, authoritative: authoritative);
    return result;
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(serverVisibilityProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
          child: Row(
            children: [
              const Text(
                'Мои серверы',
                style: TextStyle(
                    color: Cosmic.text, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Добавить сервер',
                icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                color: Cosmic.violetBright,
                onPressed: () => GoRouter.of(context).push('/servers/catalog'),
              ),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<MyServersResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorView(error: snapshot.error!, onRetry: _reload);
              }
              final result = snapshot.data!;
              if (result.subscription == null) return const _NoSubscriptionView();
              if (result.servers.isEmpty) return const _EmptyServersView();
              // Hide servers the user switched off in the catalog (local
              // preference). Default: everything visible.
              final visible =
                  result.servers.where((s) => !hidden.contains(s.code)).toList();
              if (visible.isEmpty) return const _AllHiddenView();
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, i) =>
                      _ServerCard(server: visible[i], onChanged: _reload),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.server, required this.onChanged});
  final MyServer server;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = server.configUrl != null;
    return Container(
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Text(server.countryFlag.isEmpty ? '🌐' : server.countryFlag,
                style: const TextStyle(fontSize: 26)),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.city ?? server.name,
                    style: const TextStyle(
                        color: Cosmic.text, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Gap(3),
                  PingLabel(host: server.pingHost, port: server.pingPort),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Cosmic.text2),
              color: Cosmic.cardHi,
              onSelected: (v) {
                switch (v) {
                  case 'vless':
                    _connect(context, ref);
                  case 'awg':
                    _connectAwg(context, ref);
                  case 'delete':
                    _delete(context, ref);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'vless',
                  enabled: reachable,
                  child: const Text('Подключить (VLESS)'),
                ),
                const PopupMenuItem(
                  value: 'awg',
                  child: Text('Подключить (AmneziaWG)'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Удалить', style: TextStyle(color: Cosmic.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Добавляем ${server.city ?? server.code}…')));
    await ref.read(serverProfileSyncProvider).importServer(server.configUrl!);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('${server.city ?? server.code} добавлен — нажмите «Подключить» вверху'),
    ));
  }

  Future<void> _connectAwg(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Готовлю AmneziaWG для ${server.city ?? server.code}…'),
      duration: const Duration(seconds: 6),
    ));
    try {
      final conf = await ref
          .read(subscriptionApiProvider)
          .awgConfig(accessToken: auth.accessToken, slotId: server.slotId);
      final ok = await ref.read(serverProfileSyncProvider).importAwgConfig(conf);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? '${server.city ?? server.code} (AmneziaWG) добавлен — нажмите «Подключить» вверху'
            : 'Не удалось импортировать AmneziaWG-конфиг'),
      ));
    } on SubscriptionApiException catch (e) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      final msg = switch (e.code) {
        SubscriptionErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
        SubscriptionErrorCode.network => 'Нет связи с сервером.',
        SubscriptionErrorCode.unknown => e.message,
      };
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сервер?'),
        content: Text(
          '«${server.city ?? server.name}» будет удалён из вашей подписки '
          '— и здесь, и в Telegram-боте. Действие необратимо.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Удаляем ${server.city ?? server.code}…')));
    try {
      await ref
          .read(subscriptionApiProvider)
          .deleteServer(accessToken: auth.accessToken, slotId: server.slotId);
      await ref.read(serverProfileSyncProvider).removeProfileByUrl(server.configUrl);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
          SnackBar(content: Text('«${server.city ?? server.code}» удалён')));
      onChanged();
    } on SubscriptionApiException catch (e) {
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      final msg = switch (e.code) {
        SubscriptionErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
        SubscriptionErrorCode.network => 'Нет связи с сервером.',
        SubscriptionErrorCode.unknown => 'Не удалось удалить: ${e.message}',
      };
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

class _NoSubscriptionView extends StatelessWidget {
  const _NoSubscriptionView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 44, color: Cosmic.text2),
            Gap(14),
            Text(
              'У вас нет активной подписки.\n'
              'Активируйте её в Telegram-боте — серверы появятся здесь автоматически.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Cosmic.text2, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyServersView extends StatelessWidget {
  const _EmptyServersView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Подписка активна, но серверы ещё не подключены.\n'
          'Активируйте серверы в Telegram-боте.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Cosmic.text2, height: 1.4),
        ),
      ),
    );
  }
}

class _AllHiddenView extends StatelessWidget {
  const _AllHiddenView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_off_outlined, size: 40, color: Cosmic.text2),
            const Gap(12),
            const Text(
              'Все серверы скрыты с главной.\nВключите нужные в каталоге серверов.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Cosmic.text2, height: 1.4),
            ),
            const Gap(14),
            FilledButton.tonalIcon(
              onPressed: () => GoRouter.of(context).push('/servers/catalog'),
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: const Text('Открыть каталог'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unauthorized = error is SubscriptionApiException &&
        (error as SubscriptionApiException).code == SubscriptionErrorCode.unauthorized;
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
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Cosmic.text2)),
          const Gap(14),
          // On an expired session, retrying just loops — log out so the
          // router redirects to the login screen.
          unauthorized
              ? FilledButton(
                  onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                  child: const Text('Войти'),
                )
              : FilledButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
