// In-app Account screen — TZ §14.6.
//
// Shows: email + verified badge, subscription status & expiry, devices
// counter (link to /account/devices in chunk N+1), referral code stub,
// logout button.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/api/account_api.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authNotifierProvider);

    if (auth is! AuthAuthenticated) {
      // Router redirect should not let us reach here — defensive fallback.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Аккаунт')),
      body: CosmicBackground(
        child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _AccountHeader(account: auth.account),
            const SizedBox(height: 16),
            if (!auth.account.hasTelegram) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.send_rounded, color: Color(0xFF835FFD)),
                  title: const Text('Привязать Telegram'),
                  subtitle: const Text('Подтянуть подписку и серверы из бота'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => GoRouter.of(context).push('/auth/telegram'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _SubscriptionCard(subscription: auth.subscription),
            const SizedBox(height: 16),
            _DevicesShortcut(),
            const SizedBox(height: 16),
            _ReferralStub(),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.logout),
              label: const Text('Выйти'),
              style: FilledButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).logout();
                // Router redirect picks AuthUnauthenticated → /auth/email.
              },
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final Account account;
  const _AccountHeader({required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                account.email.substring(0, 1).toUpperCase(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.email,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (account.emailVerified)
                        const Icon(Icons.verified, size: 16, color: Colors.green)
                      else
                        Icon(Icons.warning_amber,
                            size: 16, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 4),
                      Text(
                        account.emailVerified
                            ? 'Email подтверждён'
                            : 'Email не подтверждён',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (account.hasTelegram) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.send, size: 16),
                        const SizedBox(width: 4),
                        Text('Telegram привязан',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final SubscriptionSummary? subscription;
  const _SubscriptionCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = subscription;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Подписка',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (sub == null)
              Text(
                'У вас пока нет активной подписки. '
                'Trial 7 дней начинается автоматически при первом подключении.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              _Row(label: 'Статус', value: _localiseStatus(sub.status)),
              if (sub.expiresAt != null)
                _Row(label: 'Действует до', value: _formatDate(sub.expiresAt!)),
              _Row(
                label: 'Лимит устройств',
                value: '${sub.maxDevices}',
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => GoRouter.of(context).push('/tariffs'),
              child: Text(sub == null ? 'Выбрать тариф' : 'Продлить подписку'),
            ),
          ],
        ),
      ),
    );
  }

  String _localiseStatus(String s) => switch (s.toLowerCase()) {
        'active' => 'Активна',
        'trial' => 'Trial',
        'pending_payment' => 'Ожидает оплаты',
        'expired' => 'Истекла',
        'suspended' => 'Приостановлена',
        _ => s,
      };

  String _formatDate(DateTime dt) {
    final l = dt.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    return '$dd.$mm.${l.year}';
  }
}

class _DevicesShortcut extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.devices),
        title: const Text('Мои устройства'),
        subtitle: const Text('Список и управление'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/account/devices'),
      ),
    );
  }
}

class _ReferralStub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.card_giftcard),
        title: Text('Реферальная программа'),
        subtitle: Text('Скоро'),
        enabled: false,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
