# R-VPN+

Cross-platform VPN application by **Xenex Networks LLC**.

R-VPN+ is the native client for the R-VPN+ service — available on Android,
iOS, Windows, macOS, and Linux. It provides secure, private connectivity
through the R-VPN+ server network with built-in support for modern protocols.

**Status:** under active development. Phase 0 in progress.

## Features (planned)

- One-click connect with **AI Smart Connect** — automatic best-server selection
- **VLESS + Reality** and **AmneziaWG** protocols built-in (no separate client needed)
- Email + OTP authentication, optional Telegram linking
- Up to **10 devices** per account
- Three routing modes: All-through-VPN, Bypass-RU, Bypass-CN
- Native chat support with AI agent
- In-app subscription management (Apple IAP / Google Play Billing / direct payment methods)
- Full localisation: Russian, English, Chinese

## Platforms

| Platform | Status |
|---|---|
| Android | Phase 1 (in progress) |
| Windows | Phase 1 (in progress) |
| iOS | Phase 2 |
| macOS | Phase 2 |
| Linux | Phase 3 |

## Downloads

Once Phase 1 ships:
- **App stores:** [app.rvpn.plus](https://app.rvpn.plus)
- **Direct download:** [plus.rvpn.app](https://plus.rvpn.app)

## Development

R-VPN+ is built with Flutter (Dart) on top of [sing-box](https://github.com/SagerNet/sing-box)
as the underlying VPN engine. The project is a fork of
[Hiddify-Next](https://github.com/hiddify/hiddify-next) — see [CREDITS.md](CREDITS.md)
for full attribution.

### Building locally

```bash
# Requirements: Flutter 3.44+, Android SDK 36 + NDK r27, JDK 21
flutter pub get
flutter run                  # debug, on a connected device
flutter build apk --release  # Android release
flutter build linux          # Linux desktop
```

For full build documentation including iOS/macOS/Windows targets, see
[`docs/BUILD.md`](docs/BUILD.md) (TBD).

## Licence

R-VPN+ is licensed under **GPL-3.0** (same as upstream Hiddify-Next). See
[LICENSE](LICENSE) for the full terms.

## Links

- **Marketing site:** [rvpn.app](https://rvpn.app)
- **App landing:** [plus.rvpn.app](https://plus.rvpn.app)
- **API base:** `api.rvpn.app`
- **Bot:** [@rvpnplus_bot](https://t.me/rvpnplus_bot)
- **Support:** support@rocketvpn.net

---

© 2026 Xenex Networks LLC. All rights reserved.
