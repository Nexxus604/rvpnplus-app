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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    final access = await _storage.read(key: _kAccessTokenKey);
    final refresh = await _storage.read(key: _kRefreshTokenKey);
    if (access == null || refresh == null) return null;
    return StoredTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccessTokenKey, value: accessToken);
    await _storage.write(key: _kRefreshTokenKey, value: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccessTokenKey);
    await _storage.delete(key: _kRefreshTokenKey);
  }
}

final secureTokenStoreProvider = Provider<SecureTokenStore>((_) {
  return SecureTokenStore();
});
