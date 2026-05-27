// R-VPN+ tariffs / payment screen (TZ §17, Phase 1).
//
// Lists plans from /v1/tariffs. "Оплатить" opens the plan's Tribute link
// (Telegram / Tribute mini-app) via url_launcher; the Tribute webhook then
// credits the subscription, which appears on the account/home on refresh.

import 'package:flutter/material.dart';
import 'package:hiddify/core/api/tariffs_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class TariffsPage extends ConsumerStatefulWidget {
  const TariffsPage({super.key});

  @override
  ConsumerState<TariffsPage> createState() => _TariffsPageState();
}

class _TariffsPageState extends ConsumerState<TariffsPage> {
  late Future<List<Tariff>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Tariff>> _load() {
    final auth = ref.read(authNotifierProvider);
    if (auth is! AuthAuthenticated) {
      throw const TariffsApiException(
          TariffsErrorCode.unauthorized, 'Not logged in');
    }
    return ref.read(tariffsApiProvider).list(accessToken: auth.accessToken);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _pay(Tariff tariff) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!tariff.payable) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Оплата этого тарифа доступна в Telegram-боте.'),
      ));
      return;
    }
    final uri = Uri.parse(tariff.tributeLink!);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Не удалось открыть оплату. Попробуйте ещё раз.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Тарифы')),
      body: CosmicBackground(
        child: SafeArea(
          child: FutureBuilder<List<Tariff>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorView(error: snapshot.error!, onRetry: _reload);
              }
              final tariffs = snapshot.data ?? const <Tariff>[];
              if (tariffs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('Тарифы пока недоступны.',
                        style: TextStyle(color: Cosmic.text2)),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: tariffs.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == tariffs.length) return const _PayHint();
                  return _TariffCard(tariff: tariffs[i], onPay: () => _pay(tariffs[i]));
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TariffCard extends StatelessWidget {
  const _TariffCard({required this.tariff, required this.onPay});
  final Tariff tariff;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Cosmic.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  tariff.title,
                  style: const TextStyle(
                      color: Cosmic.text, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${tariff.priceRub.toStringAsFixed(0)} ₽',
                style: const TextStyle(
                    color: Cosmic.violetBright,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_period(tariff.durationDays)} · до ${tariff.maxDevices} устройств',
            style: const TextStyle(color: Cosmic.text2, fontSize: 13),
          ),
          if (tariff.description != null && tariff.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tariff.description!,
                style: const TextStyle(color: Cosmic.text2, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPay,
              child: const Text('Оплатить'),
            ),
          ),
        ],
      ),
    );
  }

  String _period(int days) => switch (days) {
        30 || 31 => '1 месяц',
        90 || 91 || 92 => '3 месяца',
        180 || 182 || 183 => '6 месяцев',
        360 || 365 || 366 => '1 год',
        _ => '$days дней',
      };
}

class _PayHint extends StatelessWidget {
  const _PayHint();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 15, color: Cosmic.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Оплата проходит через Telegram (Tribute). После оплаты подписка '
              'появится в приложении автоматически.',
              style: TextStyle(color: Cosmic.muted, fontSize: 12, height: 1.4),
            ),
          ),
        ],
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
    final msg = error is TariffsApiException
        ? switch ((error as TariffsApiException).code) {
            TariffsErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
            TariffsErrorCode.network => 'Нет связи с сервером.',
            TariffsErrorCode.unknown => (error as TariffsApiException).message,
          }
        : 'Что-то пошло не так';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 44, color: Cosmic.text2),
          const SizedBox(height: 14),
          Text(msg, style: const TextStyle(color: Cosmic.text2)),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
