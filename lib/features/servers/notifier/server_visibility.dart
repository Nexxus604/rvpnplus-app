// Local, persisted preference for which provisioned servers are shown on the
// Home "Мои серверы" list. Stores the HIDDEN set — so by default (empty) every
// server the account has is visible, and the user can hide some in the catalog
// without deprovisioning them.

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHiddenKey = 'hidden_server_codes';

class ServerVisibility extends StateNotifier<Set<String>> {
  ServerVisibility() : super(const {}) {
    _load();
  }

  SharedPreferences? _prefs;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = (_prefs!.getStringList(_kHiddenKey) ?? const <String>[]).toSet();
  }

  bool isVisible(String code) => !state.contains(code);

  Future<void> setVisible(String code, bool visible) async {
    final next = Set<String>.from(state);
    if (visible) {
      next.remove(code);
    } else {
      next.add(code);
    }
    state = next;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_kHiddenKey, next.toList());
  }
}

/// The set of HIDDEN server codes. A server is visible on Home when its code
/// is NOT in this set.
final serverVisibilityProvider =
    StateNotifierProvider<ServerVisibility, Set<String>>((ref) => ServerVisibility());
