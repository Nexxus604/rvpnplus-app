// Keeps Hiddify profiles in sync with the account's R-VPN+ servers.
//
// Our servers each map to a Marzban subscription URL on a *.rvpn.app
// node. We import each as a Hiddify "remote" profile (upsertRemote) and
// reconcile: any rvpn.app profile whose URL is no longer in the
// account's server list (e.g. the user removed it in the Telegram bot)
// gets deleted, so the app mirrors the bot both ways.
//
// All operations are best-effort and never throw to the caller — a
// profile-store hiccup must not break the Servers screen.

import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ServerProfileSync {
  final Ref _ref;
  const ServerProfileSync(this._ref);

  ProfileRepository? get _repo =>
      _ref.read(profileRepositoryProvider).valueOrNull;

  bool _looksLikeOurs(String url) =>
      url.contains('rvpn.app') && url.contains('/sub/');

  Future<List<ProfileEntity>> _allProfiles() async {
    final repo = _repo;
    if (repo == null) return const [];
    try {
      final either = await repo.watchAll().first;
      return either.getOrElse((_) => const []);
    } catch (_) {
      return const [];
    }
  }

  /// Add (or refresh) the Hiddify profile for a server's sub URL.
  Future<void> importServer(String configUrl) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.upsertRemote(configUrl).run();
    } catch (_) {/* surfaced to user via the Servers screen snackbar */}
  }

  /// Import a raw AmneziaWG .conf as a local profile (sing-box `awg`).
  /// Returns true on success so the caller can surface a clear error.
  Future<bool> importAwgConfig(String content) async {
    final repo = _repo;
    if (repo == null) return false;
    final result = await repo.addLocal(content).run();
    return result.isRight();
  }

  /// Select a server via VLESS: import its sub URL and make it the ACTIVE
  /// profile (a newly-imported profile isn't active by default). The Home
  /// connect button then connects to it.
  Future<bool> selectRemote(String configUrl) async {
    final repo = _repo;
    if (repo == null) return false;
    try {
      await repo.upsertRemote(configUrl).run();
      String? id;
      for (final p in await _allProfiles()) {
        if (p is RemoteProfileEntity && p.url == configUrl) {
          id = p.id;
          break;
        }
      }
      if (id == null) return false;
      final res = await repo.setAsActive(id).run();
      return res.isRight();
    } catch (_) {
      return false;
    }
  }

  /// Select a server via AmneziaWG: replace any previously-imported local
  /// (AWG) profile with this one and make it active. We keep at most one AWG
  /// profile (the currently-selected AWG server) so there's no buildup and
  /// the sole local is unambiguously the active one.
  Future<bool> selectLocal(String content) async {
    final repo = _repo;
    if (repo == null) return false;
    try {
      // Drop existing local (AWG) profiles first.
      for (final p in await _allProfiles()) {
        if (p is LocalProfileEntity) {
          await repo.deleteById(p.id, p.active).run();
        }
      }
      await repo.addLocal(content).run();
      String? id;
      for (final p in await _allProfiles()) {
        if (p is LocalProfileEntity) {
          id = p.id;
          break;
        }
      }
      if (id == null) return false;
      final res = await repo.setAsActive(id).run();
      return res.isRight();
    } catch (_) {
      return false;
    }
  }

  /// Make an already-imported profile active by its id (used to restore the
  /// previously-active profile after a speed test).
  Future<void> setActive(String id) async {
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.setAsActive(id).run();
    } catch (_) {}
  }

  /// Delete the Hiddify profile whose URL matches [configUrl], if present.
  Future<void> removeProfileByUrl(String? configUrl) async {
    if (configUrl == null) return;
    final repo = _repo;
    if (repo == null) return;
    try {
      for (final p in await _allProfiles()) {
        if (p is RemoteProfileEntity && p.url == configUrl) {
          await repo.deleteById(p.id, p.active).run();
        }
      }
    } catch (_) {}
  }

  /// Make the profile store mirror the account.
  ///
  /// - FOREIGN remote profiles (not our rvpn.app /sub/ URL) are always
  ///   removed — e.g. a leftover test subscription from another VPN that was
  ///   lingering as the active profile and silently auto-connecting. They
  ///   never belong in R-VPN+.
  /// - OUR orphans (rvpn.app profiles no longer in [currentUrls]) are removed
  ///   only when [authoritative] is true — i.e. the caller knows the server
  ///   list is complete (active subscription, non-empty). This guards against
  ///   a transient empty/partial /v1/subscription/servers response (mid
  ///   renewal, a node whose config_url is momentarily null) wiping the
  ///   user's working profiles — including the active one, which would drop
  ///   the VPN.
  ///
  /// Local profiles (imported AmneziaWG .conf) have no URL and are left alone.
  Future<int> reconcile(Set<String> currentUrls, {bool authoritative = true}) async {
    final repo = _repo;
    if (repo == null) return 0;
    var removed = 0;
    try {
      for (final p in await _allProfiles()) {
        if (p is! RemoteProfileEntity) continue;
        if (currentUrls.contains(p.url)) continue;
        // Foreign → always; our orphans → only on an authoritative list.
        if (!_looksLikeOurs(p.url) || authoritative) {
          await repo.deleteById(p.id, p.active).run();
          removed++;
        }
      }
    } catch (_) {}
    return removed;
  }
}

final serverProfileSyncProvider = Provider<ServerProfileSync>((ref) {
  return ServerProfileSync(ref);
});
