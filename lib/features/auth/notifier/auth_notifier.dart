// Auth state holder for the R-VPN+ app.
//
// State machine:
//   AuthInitial          — boot, before we've checked persisted token
//   AuthUnauthenticated  — no valid token; show /auth/email
//   AuthPendingOtp       — OTP sent, waiting for user to enter code
//   AuthAuthenticated    — JWT + Account in hand; show /home
//
// Token persistence: shared_preferences for now. TODO: migrate to
// flutter_secure_storage (Keychain/Keystore/DPAPI) — see TZ §22.2.

import 'package:hiddify/core/api/auth_api.dart';
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
  final String accessToken;
  final String refreshToken;
  const AuthAuthenticated({
    required this.account,
    required this.accessToken,
    required this.refreshToken,
  });
}

const _kAccessTokenKey = 'app_auth_access_token';
const _kRefreshTokenKey = 'app_auth_refresh_token';
const _kAccountEmailKey = 'app_auth_account_email';
const _kAccountIdKey = 'app_auth_account_id';

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _loadPersisted();
    return const AuthInitial();
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccessTokenKey);
    final refresh = prefs.getString(_kRefreshTokenKey);
    final email = prefs.getString(_kAccountEmailKey);
    final id = prefs.getInt(_kAccountIdKey);
    if (access != null && refresh != null && email != null && id != null) {
      // TODO(next chunk): probe /v1/account on boot; on 401, attempt
      // refresh; on refresh failure, fall to AuthUnauthenticated.
      state = AuthAuthenticated(
        accessToken: access,
        refreshToken: refresh,
        account: Account(
          id: id,
          email: email,
          emailVerified: true,
          locale: 'ru',
          hasTelegram: false,
        ),
      );
    } else {
      state = const AuthUnauthenticated();
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
      state = AuthAuthenticated(
        account: current.account,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );
      return true;
    } on AuthApiException catch (e) {
      // Refresh failed → wipe stored tokens, force re-login.
      await logout();
      state = AuthUnauthenticated(lastError: e.message);
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessTokenKey);
    await prefs.remove(_kRefreshTokenKey);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessTokenKey, accessToken);
    await prefs.setString(_kRefreshTokenKey, refreshToken);
    await prefs.setString(_kAccountEmailKey, accountEmail);
    await prefs.setInt(_kAccountIdKey, accountId);
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
