// R-VPN+ "Серверы" screen (TZ §11 + §14.5).
//
// Default mode: groups nodes by country. Tapping a country expands to
// show the cities/nodes within. Advanced mode (toggle TBD in settings)
// will surface per-node latency / load / protocol picker.
//
// AI Smart Connect (TZ §11.4) and one-tap connect are wired in a
// follow-up chunk once we have the per-node config endpoint
// (/v1/nodes/{id}/config) and a place to inject the resulting sing-box
// outbound into Hiddify's active profile.

import 'package:flutter/material.dart';
import 'package:hiddify/core/api/nodes_api.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
  late Future<List<NodeItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<NodeItem>> _load() {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      throw const NodesApiException(
          NodesErrorCode.unauthorized, 'Not logged in');
    }
    return ref.read(nodesApiProvider).list(accessToken: auth.accessToken);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Серверы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<NodeItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _reload);
          }
          final items = snapshot.data ?? const <NodeItem>[];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Серверы недоступны.\nПопробуйте обновить позже.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _CountryGroupedList(items: items);
        },
      ),
    );
  }
}

class _CountryGroupedList extends ConsumerWidget {
  final List<NodeItem> items;
  const _CountryGroupedList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = <String, List<NodeItem>>{};
    for (final n in items) {
      groups.putIfAbsent(n.countryCode, () => []).add(n);
    }
    final countryCodes = groups.keys.toList()..sort();

    return ListView.builder(
      itemCount: countryCodes.length,
      itemBuilder: (context, i) {
        final cc = countryCodes[i];
        final nodes = groups[cc]!;
        final flag = nodes.first.countryFlag;
        return _CountryGroup(
          flag: flag,
          countryCode: cc,
          nodes: nodes,
        );
      },
    );
  }
}

class _CountryGroup extends StatelessWidget {
  final String flag;
  final String countryCode;
  final List<NodeItem> nodes;
  const _CountryGroup({
    required this.flag,
    required this.countryCode,
    required this.nodes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Group cities within country.
    final cities = <String, List<NodeItem>>{};
    for (final n in nodes) {
      cities.putIfAbsent(n.city ?? '—', () => []).add(n);
    }
    return ExpansionTile(
      leading: Text(flag.isEmpty ? '🏳️' : flag,
          style: const TextStyle(fontSize: 28)),
      title: Text(_countryName(countryCode),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          )),
      subtitle: Text('${nodes.length} ${_pluralize(nodes.length, "сервер", "сервера", "серверов")}'),
      children: cities.entries.map((entry) {
        return _CityRow(city: entry.key, nodes: entry.value);
      }).toList(),
    );
  }

  String _countryName(String cc) => switch (cc.toUpperCase()) {
        'RU' => 'Россия',
        'NL' => 'Нидерланды',
        'DE' => 'Германия',
        'KZ' => 'Казахстан',
        'US' => 'США',
        'GB' => 'Великобритания',
        'FR' => 'Франция',
        'TR' => 'Турция',
        'AM' => 'Армения',
        'GE' => 'Грузия',
        _ => cc,
      };

  String _pluralize(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
    return many;
  }
}

class _CityRow extends ConsumerWidget {
  final String city;
  final List<NodeItem> nodes;
  const _CityRow({required this.city, required this.nodes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final avgLoad = nodes.isEmpty
        ? 0
        : (nodes.map((n) => n.loadPercent).reduce((a, b) => a + b) / nodes.length).round();
    // For one-tap connect we pick the lightest-loaded node in this city.
    final pick = [...nodes]..sort((a, b) => a.loadPercent.compareTo(b.loadPercent));
    final preferred = pick.first;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 72, right: 16),
      title: Text(city),
      subtitle: Text(
        'Нагрузка: ~$avgLoad% • ${nodes.length} ${nodes.length == 1 ? "нода" : "нод"}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: nodes.any((n) => n.isPremium)
          ? const Icon(Icons.workspace_premium, color: Colors.amber)
          : null,
      onTap: () => _onTap(context, ref, preferred),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref, NodeItem node) async {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) return;
    // Show transient spinner snackbar.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Получаем конфиг для ${node.code}…'),
      duration: const Duration(seconds: 4),
    ));
    try {
      final cfg = await ref.read(nodesApiProvider).getConfig(
            accessToken: auth.accessToken,
            nodeId: node.id,
          );
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      // Hand the Marzban sub URL to Hiddify's existing "Add Profile" flow.
      await ref
          .read(bottomSheetsNotifierProvider.notifier)
          .showAddProfile(url: cfg.configUrlSingbox);
    } on NodesApiException catch (e) {
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_localiseError(e))));
    }
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final msg = error is NodesApiException
        ? _localiseError(error as NodesApiException)
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

String _localiseError(NodesApiException e) => switch (e.code) {
      NodesErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
      NodesErrorCode.notFound => 'Эта нода больше недоступна.',
      NodesErrorCode.notProvisioned => 'Эта нода не подключена к вашей подписке. '
          'Добавьте её через панель в Telegram-боте.',
      NodesErrorCode.bindTelegram => 'Привяжите Telegram-аккаунт, '
          'чтобы получить доступ к серверам.',
      NodesErrorCode.noSubscription => 'У вас нет активной подписки. '
          'Откройте Telegram-бот и активируйте trial.',
      NodesErrorCode.panelUnconfigured => 'Сервер временно недоступен.',
      NodesErrorCode.network => 'Нет связи с сервером.',
      NodesErrorCode.unknown => e.message,
    };
