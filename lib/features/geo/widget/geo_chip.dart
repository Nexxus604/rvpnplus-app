// Home compact pill: shows the user's REAL IP / city / country.
// Routes to the Account screen on tap (the full detail card lives there).
//
// Design choices baked in:
//   • compact 28px-tall pill, centered, maxWidth 320 — does not eat vertical
//     real-estate from the servers list;
//   • hidden under session lock / biometric lock / unauthenticated — never
//     pokes through the lock overlay;
//   • NO long-press copy — IP is sensitive enough that the privacy-friendly
//     default wins (full detail still available via Account → IP card);
//   • when the tunnel is connected, the border switches to cosmic blue to
//     hint "this is still your REAL IP — the VPN exit is elsewhere".

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/api/geo_api.dart';
import 'package:hiddify/core/auth/biometric_lock.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/geo/notifier/my_geo_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Minimal ISO-2 → Russian country name map for the ~30 countries we routinely
// see. Falls back to the English name returned by the geo service for
// anything not listed (better than nothing; rare).
const _ruCountry = <String, String>{
  'RU': 'Россия', 'BY': 'Беларусь', 'UA': 'Украина', 'KZ': 'Казахстан',
  'AM': 'Армения', 'GE': 'Грузия', 'KG': 'Кыргызстан', 'UZ': 'Узбекистан',
  'AZ': 'Азербайджан', 'TR': 'Турция', 'AE': 'ОАЭ', 'CN': 'Китай',
  'JP': 'Япония', 'KR': 'Южная Корея', 'IN': 'Индия', 'TH': 'Таиланд',
  'VN': 'Вьетнам', 'ID': 'Индонезия',
  'NL': 'Нидерланды', 'DE': 'Германия', 'FR': 'Франция', 'GB': 'Великобритания',
  'IE': 'Ирландия', 'IT': 'Италия', 'ES': 'Испания', 'PT': 'Португалия',
  'PL': 'Польша', 'CZ': 'Чехия', 'AT': 'Австрия', 'CH': 'Швейцария',
  'SE': 'Швеция', 'NO': 'Норвегия', 'FI': 'Финляндия', 'DK': 'Дания',
  'US': 'США', 'CA': 'Канада', 'MX': 'Мексика', 'BR': 'Бразилия',
  'AR': 'Аргентина', 'AU': 'Австралия', 'NZ': 'Новая Зеландия', 'ZA': 'ЮАР',
};

/// Localise the country name when we can, otherwise keep the upstream value.
String localiseCountry(GeoInfo info) {
  final cc = (info.countryCode ?? '').toUpperCase();
  return _ruCountry[cc] ?? (info.country ?? cc);
}

String _label(GeoInfo info) {
  final city = (info.city ?? '').trim();
  final country = localiseCountry(info);
  if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
  if (city.isNotEmpty) return city;
  if (country.isNotEmpty) return country;
  return info.ip ?? '—';
}

class GeoChip extends ConsumerWidget {
  const GeoChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hide under session-lock OR biometric-lock OR unauthenticated.
    if (ref.watch(biometricLockProvider.select((s) => s.locked))) {
      return const SizedBox.shrink();
    }
    if (ref.watch(authNotifierProvider) is! AuthAuthenticated) {
      return const SizedBox.shrink();
    }

    final result = ref.watch(myGeoProvider);
    final isConnected = ref.watch(
      connectionNotifierProvider
          .select((async) => async.valueOrNull?.isConnected ?? false),
    );

    return result.when(
      loading: () => _Pill(
        connected: isConnected,
        child: const _LoadingContent(),
      ),
      error: (_, _) => _Pill(
        connected: isConnected,
        onTap: () => ref.invalidate(myGeoProvider),
        child: const _ErrorContent(),
      ),
      data: (r) {
        if (r is GeoLookupOk) {
          return _Pill(
            connected: isConnected,
            onTap: () => GoRouter.of(context).push('/account'),
            child: _OkContent(info: r.info),
          );
        }
        if (r is GeoLookupAuthExpired) return const SizedBox.shrink();
        // Network / server error — tap to retry.
        return _Pill(
          connected: isConnected,
          onTap: () => ref.invalidate(myGeoProvider),
          child: const _ErrorContent(),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.connected, required this.child, this.onTap});
  final bool connected;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      container: true,
      label: 'Ваш IP-адрес и местоположение. Нажмите, чтобы открыть подробности.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              color: Cosmic.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: connected
                      ? Cosmic.connectedBlue.withValues(alpha: .35)
                      : Colors.white.withValues(alpha: .06),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: SizedBox(height: 16, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent();
  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('📍', style: TextStyle(fontSize: 13)),
        Gap(8),
        Text(
          'Определяю местоположение…',
          style: TextStyle(
              color: Cosmic.muted, fontSize: 12.5, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent();
  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('📍', style: TextStyle(fontSize: 13)),
        Gap(8),
        Flexible(
          child: Text(
            'Местоположение недоступно',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Cosmic.text2, fontSize: 12.5),
          ),
        ),
        Gap(8),
        Icon(Icons.refresh_rounded, size: 14, color: Cosmic.text2),
      ],
    );
  }
}

class _OkContent extends StatelessWidget {
  const _OkContent({required this.info});
  final GeoInfo info;

  @override
  Widget build(BuildContext context) {
    final label = _label(info);
    final cc = (info.countryCode ?? '').toUpperCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('📍', style: TextStyle(fontSize: 13)),
        const Gap(8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Cosmic.text2,
                fontSize: 12.5,
                fontWeight: FontWeight.w500),
          ),
        ),
        if (cc.length == 2) ...[
          const Gap(8),
          Text(
            '· $cc',
            style: const TextStyle(
                color: Cosmic.muted, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
}
