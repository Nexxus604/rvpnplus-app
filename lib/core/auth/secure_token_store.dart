// Encrypted-at-rest storage for the auth token pair.
//
// Backed by flutter_secure_storage:
//   - iOS / macOS:  Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
//   - Android:      Keystore-encrypted SharedPreferences (EncryptedSharedPreferences)
//   - Windows:      DPAPI
//   - Linux:        libsecret (the `secret-tool` keyring)
//
// install_id and account_id stay in shared_preferences — they're not
// secrets and shared_preferences gives us better cold-start latency.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Audit H05: the access+refresh tokens are now persisted as a single JSON
// blob under one key. A non-atomic two-write sequence used to desync the pair
// on a process kill between writes (Keystore lag on MIUI / OS pressure),
// silently logging the user out an hour later. The legacy split-key reads
// are kept as a migration fallback so users upgrading don't lose their
// session.
const _kTokenPairKey = 'app_auth_token_pair_v2';
const _kAccessTokenKey = 'app_auth_access_token';
const _kRefreshTokenKey = 'app_auth_refresh_token';

class StoredTokens {
  final String accessToken;
  final String refreshToken;
  const StoredTokens({required this.accessToken, required this.refreshToken});
}

class SecureTokenStore {
  final FlutterSecureStorage _storage;

  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  Future<StoredTokens?> read() async {
    // Preferred: the atomic v2 pair.
    final raw = await _storage.read(key: _kTokenPairKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final a = map['a'] as String?;
        final r = map['r'] as String?;
        if (a != null && a.isNotEmpty && r != null && r.isNotEmpty) {
          return StoredTokens(accessToken: a, refreshToken: r);
        }
      } catch (_) {/* corrupt blob — fall through to legacy or null */}
    }
    // Migration: pre-v0.1.38 split keys. Read once, then the next write
    // upgrades to the v2 key.
    final access = await _storage.read(key: _kAccessTokenKey);
    final refresh = await _storage.read(key: _kRefreshTokenKey);
    if (access == null || refresh == null) return null;
    return StoredTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    final blob = jsonEncode({'a': accessToken, 'r': refreshToken});
    await _storage.write(key: _kTokenPairKey, value: blob);
    // Clear the legacy split keys so a future bug never reads a stale pair
    // from them. Best-effort — the v2 read above takes precedence anyway.
    try {
      await _storage.delete(key: _kAccessTokenKey);
      await _storage.delete(key: _kRefreshTokenKey);
    } catch (_) {/* legacy cleanup is non-critical */}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kTokenPairKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _kAccessTokenKey);
    } catch (_) {}
    try {
      await _storage.delete(key: _kRefreshTokenKey);
    } catch (_) {}
  }
}

final secureTokenStoreProvider = Provider<SecureTokenStore>((_) {
  return SecureTokenStore();
});
