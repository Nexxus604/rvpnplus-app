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

  /// Remove orphaned rvpn.app profiles — ones whose URL isn't among the
  /// account's current server URLs (deleted in the bot). [currentUrls] is
  /// the set of config_url values from /v1/subscription/servers.
  Future<int> reconcile(Set<String> currentUrls) async {
    final repo = _repo;
    if (repo == null) return 0;
    var removed = 0;
    try {
      for (final p in await _allProfiles()) {
        if (p is RemoteProfileEntity &&
            _looksLikeOurs(p.url) &&
            !currentUrls.contains(p.url)) {
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
