# Auth feature

Email + OTP authentication flow for R-VPN+ accounts (TZ §5).

## Screens

| Screen | Route | Purpose |
|---|---|---|
| `email_input_page` | `/auth/email` | User enters email → backend sends OTP |
| `otp_input_page` | `/auth/otp` | User enters 6-digit code → backend issues JWT + creates account if new |
| `tg_link_page` | `/auth/telegram` | (Optional) link existing bot user via deep link |

## State

`auth_notifier.dart` — Riverpod notifier holding `AuthState`:
- `unknown` (initial, while loading from secure storage)
- `unauthenticated`
- `pendingOtp` (awaiting code after email submission)
- `authenticated` (JWT + refresh in secure storage, account loaded)

## Backend dependencies

API endpoints used (all under `https://api.rvpn.app/v1/`):
- `POST /auth/otp/request` — send OTP to email
- `POST /auth/otp/verify` — verify OTP, get JWT + account
- `POST /auth/refresh` — refresh access token
- `POST /auth/logout` — revoke device

These are stubbed in `app_api` skeleton (only `/health` and `/version`
implemented in Phase 0). They will be filled out in Phase 1 after the
Postmark email-sending infrastructure is set up.

## Persistence

JWT access + refresh tokens stored via `flutter_secure_storage`
(Keychain on iOS/macOS, Keystore on Android, DPAPI on Windows,
libsecret on Linux). Email + account metadata cached in shared prefs.
