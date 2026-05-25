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
//   - account_id + email:    shared_preferences. Not secrets, and faster
//     cold-start read than secure storage.
//
// Boot flow (TZ §5.5):
//   1. Load persisted tokens + cached account from storage.
//   2. If present → state = AuthAuthenticated (cached values).
//   3. Probe /v1/account asynchronously to refresh data + validate token.
//   4. On 401 → attempt /v1/auth/refresh; on success retry probe.
//   5. On refresh failure → logout (state → AuthUnauthenticated).

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

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _bootstrap();
    return const AuthInitial();
  }

  /// Called once on app start: load persisted tokens, hydrate state with
  /// cached Account, then validate against /v1/account.
  Future<void> _bootstrap() async {
    final store = ref.read(secureTokenStoreProvider);
    final tokens = await store.read();
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString(_kAccountEmailKey);
    final cachedId = prefs.getInt(_kAccountIdKey);

    if (tokens == null || cachedEmail == null || cachedId == null) {
      state = const AuthUnauthenticated();
      return;
    }

    // Optimistic: assume cached data is good. Router shows /home.
    state = AuthAuthenticated(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      account: Account(
        id: cachedId,
        email: cachedEmail,
        emailVerified: true,
        locale: 'ru',
        hasTelegram: false,
      ),
    );

    // Validate + refresh details in the background.
    await _probeAccount();
  }

  /// Calls /v1/account; on 401 tries refresh once.
  Future<void> _probeAccount() async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    try {
      final details =
          await ref.read(accountApiProvider).get(accessToken: current.accessToken);
      state = current.copyWith(
        account: details.account,
        subscription: details.subscription,
      );
    } on AccountApiException catch (e) {
      if (e.code == AccountErrorCode.unauthorized) {
        final refreshed = await refreshAccess();
        if (refreshed) {
          await _probeAccount();
        }
      }
      // network / unknown — keep cached state; user sees offline-ish UI.
    }
  }

  Future<void> requestOtp({required String email, String purpose = 'login'}) async {
    state = const AuthUnauthenticated();
    try {
      await ref.read(authApiProvider).requestOtp(email: email, purpose: purpose);
      state = AuthPendingOtp(email: email, purpose: purpose);
    } on AuthApiException catch (e) {
      state = AuthUnauthenticated(lastError: e.message);
      rethrow;
    }
  }

  Future<void> verifyOtp(String code) async {
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
      );
      state = AuthAuthenticated(
        account: result.account,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      // Pull subscription data immediately.
      unawaited(_probeAccount());
    } on AuthApiException catch (e) {
      state = AuthPendingOtp(
        email: current.email,
        purpose: current.purpose,
        lastError: e.message,
      );
      rethrow;
    }
  }

  /// Exchange the stored refresh token for a fresh access token, rotating
  /// the refresh token in the process. Falls to Unauthenticated on failure.
  Future<bool> refreshAccess() async {
    final current = state;
    if (current is! AuthAuthenticated) return false;
    try {
      final result =
          await ref.read(authApiProvider).refresh(refreshToken: current.refreshToken);
      await _persist(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        accountId: current.account.id,
        accountEmail: current.account.email,
      );
      state = current.copyWith(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      return true;
    } on AuthApiException catch (e) {
      await logout();
      state = AuthUnauthenticated(lastError: e.message);
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(secureTokenStoreProvider).clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccountEmailKey);
    await prefs.remove(_kAccountIdKey);
    state = const AuthUnauthenticated();
  }

  void backToEmail() {
    state = const AuthUnauthenticated();
  }

  Future<void> _persist({
    required String accessToken,
    required String refreshToken,
    required int accountId,
    required String accountEmail,
  }) async {
    await ref.read(secureTokenStoreProvider).write(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccountEmailKey, accountEmail);
    await prefs.setInt(_kAccountIdKey, accountId);
  }
}

// Lightweight fire-and-forget helper without a hard dependency on
// dart:async (it's already in core, but kept inline for clarity).
void unawaited(Future<void> f) {
  f.catchError((_) {
    // Errors handled inside _probeAccount; no rethrow here.
  });
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
