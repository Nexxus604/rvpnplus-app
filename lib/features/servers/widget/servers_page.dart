// R-VPN+ "Мои серверы" — the account's real provisioned servers,
// synced from the Telegram bot via /v1/subscription/servers.
//
// Each server carries its Marzban subscription URL; tapping it hands the
// URL to Hiddify's Add-Profile flow so the user can connect. Servers the
// user activates/deactivates in the bot appear/disappear here on refresh
// (read-sync). Global node browsing lives in NodesApi/ServersPage history
// but is no longer the primary surface — users see THEIR servers.

import 'package:flutter/material.dart';
import 'package:hiddify/core/api/subscription_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/servers/widget/server_profile_sync.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
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
    // Capture before await — this State may be disposed by the time the
    // request resolves; the captured objects outlive it (M01 class).
    final api = ref.read(subscriptionApiProvider);
    final sync = ref.read(serverProfileSyncProvider);
    final result = await api.myServers(accessToken: auth.accessToken);
    // Read-sync: drop Hiddify profiles for servers no longer in the
    // subscription (e.g. removed in the bot).
    final currentUrls = result.servers
        .map((s) => s.configUrl)
        .whereType<String>()
        .toSet();
    await sync.reconcile(currentUrls);
    return result;
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои серверы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<MyServersResult>(
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
            return const _NoSubscriptionView();
          }
          if (result.servers.isEmpty) {
            return const _EmptyServersView();
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: _GroupedServerList(
              servers: result.servers,
              onChanged: _reload,
            ),
          );
        },
      ),
    );
  }
}

class _GroupedServerList extends ConsumerWidget {
  final List<MyServer> servers;
  final VoidCallback onChanged;
  const _GroupedServerList({required this.servers, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by country for a tidy list.
    final groups = <String, List<MyServer>>{};
    for (final s in servers) {
      groups.putIfAbsent(s.countryCode, () => []).add(s);
    }
    final countryCodes = groups.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final cc in countryCodes) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(groups[cc]!.first.countryFlag,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(
                  groups[cc]!.first.countryName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          for (final s in groups[cc]!)
            _ServerTile(server: s, onChanged: onChanged),
        ],
      ],
    );
  }
}

class _ServerTile extends ConsumerWidget {
  final MyServer server;
  final VoidCallback onChanged;
  const _ServerTile({required this.server, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reachable = server.configUrl != null;
    return ListTile(
      leading: const Icon(Icons.dns_outlined),
      title: Text(server.city ?? server.name),
      subtitle: Text(
        reachable ? 'Нагрузка: ~${server.loadPercent}%' : 'Временно недоступен',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Добавить и подключиться',
            onPressed: reachable ? () => _connect(context, ref) : null,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            tooltip: 'Удалить сервер',
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Добавляем ${server.city ?? server.code}…'),
      duration: const Duration(seconds: 2),
    ));
    await ref.read(serverProfileSyncProvider).importServer(server.configUrl!);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('${server.city ?? server.code} добавлен — нажмите «Подключить» на главном'),
    ));
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
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена')),
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
    final subApi = ref.read(subscriptionApiProvider);
    final sync = ref.read(serverProfileSyncProvider);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Удаляем ${server.city ?? server.code}…'),
    ));
    try {
      await subApi.deleteServer(accessToken: auth.accessToken, slotId: server.slotId);
      // Drop the matching Hiddify profile too, so it's gone from connect.
      await sync.removeProfileByUrl(server.configUrl);
      if (!context.mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('«${server.city ?? server.code}» удалён'),
      ));
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.workspace_premium_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'У вас нет активной подписки.\n'
              'Активируйте её в Telegram-боте — серверы появятся здесь автоматически.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
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
        padding: EdgeInsets.all(32),
        child: Text(
          'Подписка активна, но серверы ещё не подключены.\n'
          'Активируйте серверы в Telegram-боте.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

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
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text(msg),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
