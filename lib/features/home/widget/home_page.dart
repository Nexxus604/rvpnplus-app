// R-VPN+ cosmic home: the connect button on top, the account's real servers
// (synced with the Telegram bot) listed below. Starfield backdrop. Servers are
// fetched from /v1/subscription/servers and kept in sync with Hiddify profiles
// (see ServerProfileSync); tapping connects, the trash icon deletes both here
// and in the bot.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/api/subscription_api.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/connection_button_fx.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/servers/notifier/server_prefs.dart';
import 'package:hiddify/features/servers/notifier/server_visibility.dart';
import 'package:hiddify/features/servers/widget/ping_label.dart';
import 'package:hiddify/features/servers/widget/server_profile_sync.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// True once the session is detected as expired (an authed call returned 401
/// and the refresh failed). While set, the whole home screen is locked: the
/// connect button and servers are greyed out and only "Войти" works, and the
/// tunnel is forced down — a logged-out user must not stay connected.
final homeLockedProvider = StateProvider<bool>((ref) => false);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    // Fresh mount (e.g. just after a re-login) starts unlocked; the first
    // server load re-locks it if the session is still bad.
    Future.microtask(() {
      if (mounted) ref.read(homeLockedProvider.notifier).state = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final locked = ref.watch(homeLockedProvider);

    // The moment the session locks, drop the tunnel.
    ref.listen<bool>(homeLockedProvider, (prev, next) {
      if (next && !(prev ?? false)) {
        ref.read(connectionNotifierProvider.notifier).abortConnection();
      }
    });

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
        // While locked, strip the toolbar actions — nothing but "Войти" works.
        actions: locked
            ? null
            : [
                IconButton(
                  tooltip: 'Серверы',
                  icon: const Icon(Icons.dns_outlined),
                  onPressed: () => GoRouter.of(context).push('/servers/catalog'),
                ),
                IconButton(
                  tooltip: 'Маршрутизация',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => ref
                      .read(bottomSheetsNotifierProvider.notifier)
                      .showQuickSettings(),
                ),
                IconButton(
                  tooltip: 'Добавить профиль',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => ref
                      .read(bottomSheetsNotifierProvider.notifier)
                      .showAddProfile(),
                ),
                IconButton(
                  tooltip: 'Аккаунт',
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: () => GoRouter.of(context).push('/account'),
                ),
                const Gap(4),
              ],
      ),
      body: Stack(
        children: [
          const CosmicBackground(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 220,
                          child: Center(
                            child: ConnectionButtonFx(child: ConnectionButton()),
                          ),
                        ),
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
          if (locked) const Positioned.fill(child: _SessionLockOverlay()),
        ],
      ),
    );
  }
}

/// Full-screen lock shown when the session has expired: a blurred grey scrim
/// that swallows all taps to the content behind, leaving only "Войти".
class _SessionLockOverlay extends ConsumerWidget {
  const _SessionLockOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // absorb taps meant for the (now disabled) UI behind
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          color: Cosmic.deepest.withValues(alpha: 0.78),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 52, color: Cosmic.text2),
                const Gap(16),
                const Text(
                  'Сессия истекла.\nВойдите заново, чтобы продолжить.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Cosmic.text, fontSize: 16, height: 1.4),
                ),
                const Gap(20),
                FilledButton.icon(
                  onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Войти'),
                ),
              ],
            ),
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

  Future<MyServersResult> _fetch(String accessToken) async {
    final result = await ref
        .read(subscriptionApiProvider)
        .myServers(accessToken: accessToken);
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

  Future<MyServersResult> _load() async {
    final notifier = ref.read(authNotifierProvider.notifier);
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      ref.read(homeLockedProvider.notifier).state = true;
      throw const SubscriptionApiException(
          SubscriptionErrorCode.unauthorized, 'Not logged in');
    }
    try {
      final result = await _fetch(auth.accessToken);
      ref.read(homeLockedProvider.notifier).state = false;
      return result;
    } on SubscriptionApiException catch (e) {
      if (e.code != SubscriptionErrorCode.unauthorized) rethrow;
      // Access token rejected — try to refresh once before giving up so a
      // long-lived session survives an expired access token silently.
      final refreshed = await notifier.refreshAccess();
      final after = ref.read(authNotifierProvider);
      if (refreshed && after is AuthAuthenticated) {
        final result = await _fetch(after.accessToken);
        ref.read(homeLockedProvider.notifier).state = false;
        return result;
      }
      // Refresh failed — the session is genuinely gone. Lock the home.
      ref.read(homeLockedProvider.notifier).state = true;
      rethrow;
    }
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
              final shown =
                  result.servers.where((s) => !hidden.contains(s.code)).toList();
              // One card per server location: an account can hold several
              // slots on the same node (multi-device) — for the connect list
              // that's just duplicate cards. Prefer a slot with a config URL.
              final byCode = <String, MyServer>{};
              for (final s in shown) {
                final existing = byCode[s.code];
                if (existing == null ||
                    (existing.configUrl == null && s.configUrl != null)) {
                  byCode[s.code] = s;
                }
              }
              final visible = byCode.values.toList();
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
    final prefs = ref.watch(serverPrefsProvider);
    final selected = prefs.selected == server.code;
    final awg = prefs.isAwg(server.code);
    return Container(
      decoration: BoxDecoration(
        color: selected ? Cosmic.cardHi : Cosmic.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? Cosmic.violet : Colors.white.withValues(alpha: .06),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: selected
            ? [BoxShadow(color: Cosmic.violet.withValues(alpha: .35), blurRadius: 14)]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _select(context, ref),
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              server.displayName,
                              style: const TextStyle(
                                  color: Cosmic.text, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (selected) ...[
                            const Gap(6),
                            const Icon(Icons.check_circle, size: 16, color: Cosmic.violetBright),
                          ],
                        ],
                      ),
                      const Gap(3),
                      Row(
                        children: [
                          PingLabel(host: server.pingHost, port: server.pingPort),
                          const Gap(8),
                          Text(
                            awg ? 'AmneziaWG' : 'VLESS',
                            style: const TextStyle(color: Cosmic.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Cosmic.text2),
                  color: Cosmic.cardHi,
                  onSelected: (v) {
                    switch (v) {
                      case 'p_vless':
                        _applyProtocol(context, ref, kProtocolVless);
                      case 'p_awg':
                        _applyProtocol(context, ref, kProtocolAwg);
                      case 'delete':
                        _delete(context, ref);
                    }
                  },
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: 'p_vless',
                      checked: !awg,
                      child: const Text('Протокол: VLESS'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'p_awg',
                      checked: awg,
                      child: const Text('Протокол: AmneziaWG'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить', style: TextStyle(color: Cosmic.error)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Select this server: import its profile via the saved protocol and make
  // it the active one (Home connect button then connects to it). Highlights
  // the card.
  Future<void> _select(BuildContext context, WidgetRef ref) async {
    final awg = ref.read(serverPrefsProvider).isAwg(server.code);
    final sync = ref.read(serverProfileSyncProvider);
    final messenger = ScaffoldMessenger.of(context);
    bool ok;
    if (awg) {
      final auth = ref.read(authNotifierProvider);
      if (auth is! AuthAuthenticated) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Готовлю AmneziaWG для «${server.displayName}»…'),
        duration: const Duration(seconds: 6),
      ));
      try {
        final conf = await ref
            .read(subscriptionApiProvider)
            .awgConfig(accessToken: auth.accessToken, slotId: server.slotId);
        ok = await sync.selectLocal(conf);
      } on SubscriptionApiException catch (e) {
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(_errMsg(e))));
        return;
      }
    } else {
      if (server.configUrl == null) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Сервер временно недоступен по VLESS')));
        return;
      }
      ok = await sync.selectRemote(server.configUrl!);
    }
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    if (ok) {
      await ref.read(serverPrefsProvider.notifier).setSelected(server.code);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Выбран «${server.displayName}» (${awg ? 'AmneziaWG' : 'VLESS'}) — нажмите «Подключить»'),
      ));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('Не удалось подготовить сервер')));
    }
  }

  Future<void> _applyProtocol(BuildContext context, WidgetRef ref, String proto) async {
    await ref.read(serverPrefsProvider.notifier).setProtocol(server.code, proto);
    // Re-apply immediately if this server is the active selection.
    if (ref.read(serverPrefsProvider).selected == server.code && context.mounted) {
      await _select(context, ref);
    }
  }

  String _errMsg(SubscriptionApiException e) => switch (e.code) {
        SubscriptionErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
        SubscriptionErrorCode.network => 'Нет связи с сервером.',
        SubscriptionErrorCode.unknown => e.message,
      };

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
