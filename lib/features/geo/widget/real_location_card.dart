// Account-screen card showing the user's REAL IP / city / country / ISP — the
// full-detail companion to the compact Home pill. Reads the same
// [myGeoProvider] so it never double-fetches.

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/api/geo_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/geo/notifier/my_geo_provider.dart';
import 'package:hiddify/features/geo/widget/geo_chip.dart' show localiseCountry;
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RealLocationCard extends ConsumerWidget {
  const RealLocationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(myGeoProvider);
    final isConnected = ref.watch(
      connectionNotifierProvider
          .select((async) => async.valueOrNull?.isConnected ?? false),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: result.when(
          loading: () => _Layout(
            isConnected: isConnected,
            loading: true,
            onRefresh: null,
            child: const _Skeleton(),
          ),
          error: (_, _) => _Layout(
            isConnected: isConnected,
            loading: false,
            onRefresh: () => ref.invalidate(myGeoProvider),
            child: const _UnavailableLine(),
          ),
          data: (r) {
            if (r is GeoLookupOk) {
              return _Layout(
                isConnected: isConnected,
                loading: false,
                onRefresh: () => ref.invalidate(myGeoProvider),
                child: _OkBody(info: r.info),
              );
            }
            if (r is GeoLookupAuthExpired) {
              // Account screen has its own auth guard; if we still land here
              // (provider not yet re-run after a transient), show the unavailable
              // state — never a misleading blank card.
              return _Layout(
                isConnected: isConnected,
                loading: false,
                onRefresh: () => ref.invalidate(myGeoProvider),
                child: const _UnavailableLine(),
              );
            }
            return _Layout(
              isConnected: isConnected,
              loading: false,
              onRefresh: () => ref.invalidate(myGeoProvider),
              child: const _UnavailableLine(),
            );
          },
        ),
      ),
    );
  }
}

class _Layout extends StatelessWidget {
  const _Layout({
    required this.isConnected,
    required this.loading,
    required this.onRefresh,
    required this.child,
  });
  final bool isConnected;
  final bool loading;
  final VoidCallback? onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ваш реальный IP',
                style: TextStyle(
                  color: Cosmic.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            // While loading, the icon is dimmed and disabled — prevents
            // tap-storms from spawning parallel /v1/geo calls.
            IconButton(
              tooltip: 'Обновить',
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              icon: Icon(
                Icons.refresh_rounded,
                color: loading
                    ? Cosmic.text2.withValues(alpha: .35)
                    : Cosmic.violetBright,
              ),
              onPressed: loading ? null : onRefresh,
            ),
          ],
        ),
        const Gap(8),
        child,
        const Gap(12),
        const Divider(color: Cosmic.section, height: 1),
        const Gap(10),
        const Text(
          'Это адрес, который сайты видят без VPN — он привязан к вашему '
          'интернет-провайдеру. Сервер VPN-выхода показан отдельно.',
          style: TextStyle(color: Cosmic.text2, fontSize: 12, height: 1.4),
        ),
        if (isConnected) ...[
          const Gap(10),
          const _VpnConnectedBanner(),
        ],
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('📍 ', style: TextStyle(fontSize: 18)),
        Text(
          'Определяю местоположение…',
          style: TextStyle(
              color: Cosmic.muted, fontSize: 14, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _UnavailableLine extends StatelessWidget {
  const _UnavailableLine();
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('📍 ', style: TextStyle(fontSize: 18)),
        Expanded(
          child: Text(
            'Местоположение недоступно. Нажмите «Обновить».',
            style: TextStyle(color: Cosmic.text2, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _OkBody extends StatelessWidget {
  const _OkBody({required this.info});
  final GeoInfo info;

  @override
  Widget build(BuildContext context) {
    final city = (info.city ?? '').trim();
    final country = localiseCountry(info);
    final headline = (city.isNotEmpty && country.isNotEmpty)
        ? '$city, $country'
        : (city.isNotEmpty ? city : country.isNotEmpty ? country : (info.ip ?? '—'));
    final cc = (info.countryCode ?? '').toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('📍 ', style: TextStyle(fontSize: 18)),
            Expanded(
              child: Text(
                headline,
                style: const TextStyle(
                  color: Cosmic.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (cc.length == 2) ...[
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Cosmic.section,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cc,
                  style: const TextStyle(
                    color: Cosmic.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        const Gap(12),
        _DetailRow(label: 'IP-адрес', value: info.ip ?? '—', mono: true),
        const Gap(6),
        _DetailRow(label: 'Провайдер', value: (info.isp ?? '').isEmpty ? '—' : info.isp!),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Cosmic.text2, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Cosmic.text,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamilyFallback:
                  mono ? const ['RobotoMono', 'monospace', 'Courier'] : null,
              fontFeatures:
                  mono ? const [FontFeature.tabularFigures()] : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _VpnConnectedBanner extends StatelessWidget {
  const _VpnConnectedBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Cosmic.connectedBlue.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Cosmic.connectedBlue.withValues(alpha: .45),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_rounded, size: 16, color: Cosmic.connectedBlue),
          Gap(8),
          Expanded(
            child: Text(
              'VPN активен. Сайтам виден IP сервера, ваш реальный IP скрыт. '
              'Этот блок показывает именно ваш реальный IP.',
              style: TextStyle(
                color: Cosmic.connectedBlue,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
