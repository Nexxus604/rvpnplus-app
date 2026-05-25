// Auth state holder for the R-VPN+ app.
//
// Phase 1 chunk 2 — minimal state machine:
//   AuthInitial          — boot, before we've checked persisted token
//   AuthUnauthenticated  — no valid token; show /auth/email
//   AuthPendingOtp       — OTP sent, waiting for user to enter code
//   AuthAuthenticated    — JWT + Account in hand; show /home
//
// Token persistence: shared_preferences for now. TODO: migrate to
// flutter_secure_storage (Keychain/Keystore/DPAPI) — see TZ §22.2.

import 'package:hiddify/core/api/auth_api.dart';
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
  const AuthAuthenticated({required this.account, required this.accessToken});
}

const _kAccessTokenKey = 'app_auth_access_token';
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
    final token = prefs.getString(_kAccessTokenKey);
    final email = prefs.getString(_kAccountEmailKey);
    final id = prefs.getInt(_kAccountIdKey);
    if (token != null && email != null && id != null) {
      // TODO(phase1-chunk3): verify token by hitting /v1/account; if
      // expired, attempt refresh; only then mark authenticated.
      state = AuthAuthenticated(
        accessToken: token,
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
    try {
      final result = await ref.read(authApiProvider).verifyOtp(
            email: current.email,
            code: code,
            purpose: current.purpose,
          );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccessTokenKey, result.accessToken);
      await prefs.setString(_kAccountEmailKey, result.account.email);
      await prefs.setInt(_kAccountIdKey, result.account.id);
      state = AuthAuthenticated(
        account: result.account,
        accessToken: result.accessToken,
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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessTokenKey);
    await prefs.remove(_kAccountEmailKey);
    await prefs.remove(_kAccountIdKey);
    state = const AuthUnauthenticated();
  }

  void backToEmail() {
    state = const AuthUnauthenticated();
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
