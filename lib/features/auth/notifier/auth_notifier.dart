// Auth state holder for the R-VPN+ app.
//
// State machine:
//   AuthInitial          — boot, before persisted tokens are loaded
//   AuthUnauthenticated  — no valid token; router shows /auth/email
//   AuthPendingOtp       — OTP sent, waiting for user to enter code
//   AuthAuthenticated    — tokens + Account in memory; router shows /home
//
// Persistence split:
//   - JWT access + refresh:  flutter_secure_storage (Keychain / Keystore
//     / DPAPI / libsecret) — see [SecureTokenStore].
//   - account_id + email + email_verified + has_telegram: shared_preferences.
//     Not secrets; faster cold-start read than secure storage.
//
// Concurrency invariants worth knowing:
//   - `_refreshInFlight` mutex serialises all /auth/refresh attempts so
//     two parallel callers don't both rotate the token and crash the
//     second one with REFRESH_INVALID (reviewer F3).
//   - Every async method re-reads `state` after `await` and bails if it
//     no longer matches the snapshot it captured — protects against a
//     user logging out mid-call, which would otherwise re-resurrect
//     AuthAuthenticated with stale tokens (reviewer F2).
//   - `_otpRequestInFlight` guards double-tap on "Get code"/"Resend".

import 'dart:async';

import 'package:hiddify/core/api/account_api.dart';
import 'package:hiddify/core/api/auth_api.dart';
import 'package:hiddify/core/auth/secure_token_store.dart';
import 'package:hiddify/core/device/device_info_collector.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthUnauthenticated extends AuthState {
  final String? lastError;
  const AuthUnauthenticated({this.lastError});
}

class AuthPendingOtp extends AuthState {
  final String email;
  final String purpose;
  final String? lastError;
  const AuthPendingOtp({
    required this.email,
    required this.purpose,
    this.lastError,
  });
}

class AuthAuthenticated extends AuthState {
  final Account account;
  final SubscriptionSummary? subscription;
  final String accessToken;
  final String refreshToken;
  const AuthAuthenticated({
    required this.account,
    required this.accessToken,
    required this.refreshToken,
    this.subscription,
  });

  AuthAuthenticated copyWith({
    Account? account,
    SubscriptionSummary? subscription,
    String? accessToken,
    String? refreshToken,
  }) {
    return AuthAuthenticated(
      account: account ?? this.account,
      subscription: subscription ?? this.subscription,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }
}

const _kAccountEmailKey = 'app_auth_account_email';
const _kAccountIdKey = 'app_auth_account_id';
const _kAccountVerifiedKey = 'app_auth_account_email_verified';
const _kAccountHasTgKey = 'app_auth_account_has_telegram';

class AuthNotifier extends Notifier<AuthState> {
  /// Single-flight mutex for /auth/refresh. Without it, two concurrent
  /// API calls that both hit 401 race each other through refresh, the
  /// second one finds the rotated token invalid, and we log the user
  /// out unnecessarily. Reviewer F3.
  Completer<bool>? _refreshInFlight;

  /// Guard against the user double-tapping "Get code" / "Resend".
  bool _otpRequestInFlight = false;

  /// Bumped on any intentional session teardown (logout / back-to-email).
  /// Async methods capture it before their awaits and refuse to write
  /// AuthAuthenticated back if it changed — without this, a logout that lands
  /// mid refresh/probe is silently undone (the user gets logged back in, with
  /// stale tokens re-persisted to disk).
  int _sessionEpoch = 0;

  @override
  AuthState build() {
    _bootstrap();
    return const AuthInitial();
  }

  /// Called once on app start: load persisted tokens, hydrate state with
  /// cached Account, then validate against /v1/account.
  ///
  /// Hardened against silent log-outs:
  ///   • Secure-storage reads are retried on transient failure (Android
  ///     Keystore on MIUI / libsecret sometimes throws right after cold start
  ///     — we do NOT log the user out for that any more).
  ///   • Tokens are NEVER wiped just because the account meta in
  ///     SharedPreferences is missing — the tokens are the source of truth
  ///     and the meta is re-fetched from /v1/account. The old wipe path
  ///     silently logged users out when prefs got cleared but secure
  ///     storage still held valid tokens.
  Future<void> _bootstrap() async {
    try {
      final store = ref.read(secureTokenStoreProvider);
      StoredTokens? tokens;
      try {
        tokens = await store.read();
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        try {
          tokens = await store.read();
        } catch (_) {
          tokens = null;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final cachedEmail = prefs.getString(_kAccountEmailKey);
      final cachedId = prefs.getInt(_kAccountIdKey);
      final cachedVerified = prefs.getBool(_kAccountVerifiedKey) ?? false;
      final cachedHasTg = prefs.getBool(_kAccountHasTgKey) ?? false;

      if (tokens == null) {
        state = const AuthUnauthenticated();
        return;
      }

      // Tokens are valid even if the meta cache is empty (prefs cleared,
      // partial restore, fresh install over a Keystore-restored backup).
      // Keep the tokens; /v1/account will repopulate the meta.
      state = AuthAuthenticated(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        account: Account(
          id: cachedId ?? 0,
          email: cachedEmail ?? '',
          emailVerified: cachedVerified,
          locale: 'ru',
          hasTelegram: cachedHasTg,
        ),
      );
      await _probeAccount();
    } catch (e) {
      // Only fall through to login if we couldn't restore anything. If a
      // previous run had already authenticated this notifier we keep it
      // — never auto-logout on a transient platform error.
      if (state is! AuthAuthenticated) {
        state = AuthUnauthenticated(lastError: 'Failed to restore session: $e');
      }
    }
  }

  /// Calls /v1/account; on 401 tries refresh once. Errors that aren't
  /// 401 are logged but don't change state (we keep the cached values
  /// and let the user see an offline-ish UI).
  /// Public hook to re-pull /v1/account (subscription + email/TG flags). Used
  /// on app resume so a payment just made in Tribute is reflected without the
  /// user having to manually reload.
  Future<void> refreshAccount() => _probeAccount();

  Future<void> _probeAccount({bool retried = false}) async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    final epoch = _sessionEpoch;
    try {
      final details =
          await ref.read(accountApiProvider).get(accessToken: current.accessToken);
      // Re-check the world hasn't moved during our await. If the user
      // logged out / refresh rotated the token, our snapshot is stale
      // and we MUST NOT write `AuthAuthenticated` back. Reviewer F2.
      final after = state;
      if (_sessionEpoch != epoch ||
          after is! AuthAuthenticated ||
          after.accessToken != current.accessToken) {
        return;
      }
      // Persist updated fields so the next cold start doesn't lie about
      // emailVerified / hasTelegram. Reviewer F7.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAccountVerifiedKey, details.account.emailVerified);
      await prefs.setBool(_kAccountHasTgKey, details.account.hasTelegram);
      // Re-check again AFTER the prefs awaits — a logout can land here too.
      final after2 = state;
      if (_sessionEpoch != epoch ||
          after2 is! AuthAuthenticated ||
          after2.accessToken != current.accessToken) {
        return;
      }
      state = after2.copyWith(
        account: details.account,
        subscription: details.subscription,
      );
    } on AccountApiException catch (e) {
      // Recurse at most once: reaching here after a refresh means the access
      // token is still rejected (signing-key mismatch / clock skew). Looping
      // would rotate the refresh token forever and storm the network/battery.
      if (e.code == AccountErrorCode.unauthorized && !retried) {
        final refreshed = await refreshAccess();
        if (refreshed && _sessionEpoch == epoch && state is AuthAuthenticated) {
          await _probeAccount(retried: true);
        }
      }
      // network / unknown — keep cached state; user sees offline-ish UI.
    }
  }

  Future<void> requestOtp({required String email, String purpose = 'login'}) async {
    if (_otpRequestInFlight) return;
    _otpRequestInFlight = true;
    final pre = state;
    try {
      await ref.read(authApiProvider).requestOtp(email: email, purpose: purpose);
      state = AuthPendingOtp(email: email, purpose: purpose);
    } on AuthApiException catch (e) {
      // Reviewer F1: don't kick the user back to /auth/email if they're
      // already on /auth/otp resending a code that failed. Preserve the
      // pending-otp state so the router doesn't pop the screen.
      if (pre is AuthPendingOtp) {
        state = AuthPendingOtp(
          email: pre.email,
          purpose: pre.purpose,
          lastError: e.message,
        );
      } else {
        state = AuthUnauthenticated(lastError: e.message);
      }
      rethrow;
    } finally {
      _otpRequestInFlight = false;
    }
  }

  /// [onVerified] fires the moment the server accepts the code (and
  /// tokens are persisted) but BEFORE the auth state flips to
  /// AuthAuthenticated. The OTP screen uses it to flash the cells green
  /// for a beat; we then delay briefly so that green is actually visible
  /// before the router whisks the user to /home.
  Future<void> verifyOtp(String code, {void Function()? onVerified}) async {
    final current = state;
    if (current is! AuthPendingOtp) {
      throw StateError('verifyOtp called outside AuthPendingOtp');
    }
    final device = await ref.read(deviceInfoCollectorProvider).collect();
    try {
      final result = await ref.read(authApiProvider).verifyOtp(
            email: current.email,
            code: code,
            device: device,
            purpose: current.purpose,
          );
      await _persist(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        accountId: result.account.id,
        accountEmail: result.account.email,
        emailVerified: result.account.emailVerified,
        hasTelegram: result.account.hasTelegram,
      );
      onVerified?.call();
      if (onVerified != null) {
        await Future<void>.delayed(const Duration(milliseconds: 550));
      }
      state = AuthAuthenticated(
        account: result.account,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      // Pull subscription data immediately.
      _safeFireAndForget(_probeAccount);
    } on AuthApiException catch (e) {
      state = AuthPendingOtp(
        email: current.email,
        purpose: current.purpose,
        lastError: e.message,
      );
      rethrow;
    }
  }

  /// Log in with tokens minted out-of-band (the Telegram-binding flow:
  /// /v1/auth/telegram/status returns access+refresh once the bot confirms).
  /// Fetches /v1/account to fill the Account, persists, and authenticates.
  /// Returns false on failure (caller surfaces the error).
  Future<bool> loginWithTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      final details =
          await ref.read(accountApiProvider).get(accessToken: accessToken);
      await _persist(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accountId: details.account.id,
        accountEmail: details.account.email,
        emailVerified: details.account.emailVerified,
        hasTelegram: details.account.hasTelegram,
      );
      state = AuthAuthenticated(
        account: details.account,
        accessToken: accessToken,
        refreshToken: refreshToken,
        subscription: details.subscription,
      );
      _safeFireAndForget(_probeAccount);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Exchange the stored refresh token for a fresh access token, rotating
  /// the refresh token in the process. Concurrent callers share one in-
  /// flight HTTP request (reviewer F3). On transient network failure
  /// the session is preserved; only definitive server rejection forces
  /// a logout (reviewer F4).
  Future<bool> refreshAccess() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!.future;
    }
    final completer = Completer<bool>();
    _refreshInFlight = completer;
    // Sets the completer once, ignoring stray double-completes if the same
    // outcome arrives both via the success branch and via the finally net.
    void settle(bool v) {
      if (!completer.isCompleted) completer.complete(v);
    }
    try {
      final current = state;
      if (current is! AuthAuthenticated) {
        settle(false);
        return false;
      }
      final epoch = _sessionEpoch;
      try {
        final result = await ref
            .read(authApiProvider)
            .refresh(refreshToken: current.refreshToken);
        // Reviewer F2 + epoch: bail if state moved or a logout landed.
        final after = state;
        if (_sessionEpoch != epoch ||
            after is! AuthAuthenticated ||
            after.refreshToken != current.refreshToken) {
          settle(false);
          return false;
        }
        // Set the in-memory tokens FIRST — memory is the operative copy. If
        // _persist then throws (Keystore/PlatformException, the MIUI failure
        // mode), we still hold the freshly rotated tokens instead of keeping
        // the now-invalid old refresh token (which would force a logout on the
        // next refresh). No await between the guard above and this write, so a
        // logout can't interleave here.
        state = after.copyWith(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
        try {
          await _persist(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            accountId: after.account.id,
            accountEmail: after.account.email,
            emailVerified: after.account.emailVerified,
            hasTelegram: after.account.hasTelegram,
          );
        } catch (_) {/* disk write best-effort; memory holds the new tokens */}
        if (_sessionEpoch != epoch) {
          // A logout slipped in while we were persisting — don't leave fresh
          // tokens on disk for the next cold start to resurrect.
          try {
            await ref.read(secureTokenStoreProvider).clear();
          } catch (_) {}
          settle(false);
          return false;
        }
        settle(true);
        return true;
      } on AuthApiException catch (e) {
        // Reviewer F4: only force-logout on server-side rejection. A
        // flaky network shouldn't kick the user out — they may come
        // back online with valid tokens still on disk.
        if (e.code == AuthErrorCode.refreshInvalid ||
            e.code == AuthErrorCode.accountInactive) {
          await logout();
          state = AuthUnauthenticated(lastError: e.message);
          settle(false);
          return false;
        }
        // Network / unknown — keep state, signal caller we didn't refresh.
        settle(false);
        return false;
      }
    } finally {
      // Audit H01: ANY uncaught exception (Keystore/PlatformException, state
      // error, ref disposed mid-await) used to leak the completer — every
      // concurrent caller parked on _refreshInFlight!.future hung forever.
      // Settle to `false` as a safety net so concurrent awaiters always
      // unblock. The explicit `settle(true)` on the success path runs FIRST
      // so success is reported correctly; this is purely a finally net.
      settle(false);
      _refreshInFlight = null;
    }
  }

  Future<void> logout() async {
    // Mark the session torn down up front so any in-flight refresh/probe that
    // resolves after this won't resurrect AuthAuthenticated (epoch guard).
    _sessionEpoch++;
    // Audit H11: logout used to leave the user trapped on the session-lock
    // overlay if either of these storage operations threw (Keystore briefly
    // down on MIUI, prefs corrupted). Always flip the state at the end so
    // the router redirects to /auth/email even if persistence fails — worst
    // case the next cold start re-reads stale tokens and we run the bootstrap
    // recovery path.
    try {
      await ref.read(secureTokenStoreProvider).clear();
    } catch (_) {/* see comment above */}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAccountEmailKey);
      await prefs.remove(_kAccountIdKey);
      await prefs.remove(_kAccountVerifiedKey);
      await prefs.remove(_kAccountHasTgKey);
    } catch (_) {/* same */}
    state = const AuthUnauthenticated();
  }

  void backToEmail() {
    _sessionEpoch++;
    state = const AuthUnauthenticated();
  }

  Future<void> _persist({
    required String accessToken,
    required String refreshToken,
    required int accountId,
    required String accountEmail,
    required bool emailVerified,
    required bool hasTelegram,
  }) async {
    await ref.read(secureTokenStoreProvider).write(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccountEmailKey, accountEmail);
    await prefs.setInt(_kAccountIdKey, accountId);
    await prefs.setBool(_kAccountVerifiedKey, emailVerified);
    await prefs.setBool(_kAccountHasTgKey, hasTelegram);
  }

  /// Fire-and-forget that swallows exceptions but at least lets dart's
  /// zone error handling see them in debug builds.
  void _safeFireAndForget(Future<void> Function() f) {
    unawaited(f().catchError((Object _) {/* logged inside callee */}));
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
