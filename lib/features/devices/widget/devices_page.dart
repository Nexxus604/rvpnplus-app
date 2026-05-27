// "Мои устройства" screen — TZ §8.4.
//
// Lists devices currently logged into the account, with a "kick" action
// per row. Tapping the trash icon revokes the device server-side; that
// device's refresh token stops working immediately.

import 'package:flutter/material.dart';
import 'package:hiddify/core/api/devices_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  late Future<List<DeviceItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DeviceItem>> _load() {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      throw const DevicesApiException(
          DevicesErrorCode.unauthorized, 'Not logged in');
    }
    return ref.read(devicesApiProvider).list(accessToken: auth.accessToken);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои устройства'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _reload,
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      body: CosmicBackground(
        child: FutureBuilder<List<DeviceItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _reload);
          }
          final items = snapshot.data ?? const <DeviceItem>[];
          if (items.isEmpty) {
            return const _EmptyView();
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                return _DeviceTile(
                  device: items[i],
                  onKick: () => _kick(items[i]),
                );
              },
            ),
          );
        },
      ),
      ),
    );
  }

  Future<void> _kick(DeviceItem d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить устройство?'),
        content: Text(
          '«${d.name ?? d.platform}» больше не сможет подключаться, '
          'пока вы не войдёте на нём заново.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) return;
    try {
      await ref
          .read(devicesApiProvider)
          .revoke(accessToken: auth.accessToken, deviceId: d.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${d.name ?? d.platform}» отключено')),
      );
      _reload();
    } on DevicesApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localiseError(e))),
      );
    }
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceItem device;
  final VoidCallback onKick;
  const _DeviceTile({required this.device, required this.onKick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (device.osVersion != null) device.osVersion,
      if (device.appVersion != null) 'v${device.appVersion}',
      'Последняя активность: ${_formatRelative(device.lastSeenAt)}',
    ].whereType<String>().join(' • ');
    return ListTile(
      leading: Icon(_iconFor(device.platform)),
      title: Text(device.name ?? device.platform),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: IconButton(
        icon: const Icon(Icons.logout),
        tooltip: 'Отключить устройство',
        onPressed: onKick,
      ),
    );
  }

  IconData _iconFor(String platform) => switch (platform) {
        'android' => Icons.android,
        'ios' => Icons.phone_iphone,
        'macos' => Icons.laptop_mac,
        'windows' => Icons.laptop_windows,
        'linux' => Icons.computer,
        _ => Icons.devices_other,
      };

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 5) return 'сейчас';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final msg = error is DevicesApiException
        ? _localiseError(error as DevicesApiException)
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

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'У вас нет активных устройств. Это странно.\n'
          'Попробуйте перезайти в аккаунт.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _localiseError(DevicesApiException e) => switch (e.code) {
      DevicesErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
      DevicesErrorCode.notFound => 'Устройство не найдено.',
      DevicesErrorCode.network => 'Нет связи с сервером.',
      DevicesErrorCode.unknown => e.message,
    };
