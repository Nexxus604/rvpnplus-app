// Per-server preferences (persisted): which server is currently SELECTED on
// Home (highlighted + its profile is the active one), and the connection
// PROTOCOL chosen for each server (VLESS by default, or AmneziaWG once the
// user picks it — sticky until switched back).

import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kProtocolVless = 'vless';
const kProtocolAwg = 'awg';

const _kSelectedKey = 'selected_server_code';
const _kProtocolKey = 'server_protocols'; // json: {code: 'vless'|'awg'}

class ServerPrefsState {
  final String? selected;
  final Map<String, String> protocol;
  const ServerPrefsState({this.selected, this.protocol = const {}});

  ServerPrefsState copyWith({String? selected, Map<String, String>? protocol, bool clearSelected = false}) =>
      ServerPrefsState(
        selected: clearSelected ? null : (selected ?? this.selected),
        protocol: protocol ?? this.protocol,
      );

  String protocolFor(String code) => protocol[code] ?? kProtocolVless;
  bool isAwg(String code) => protocolFor(code) == kProtocolAwg;
}

class ServerPrefs extends StateNotifier<ServerPrefsState> {
  ServerPrefs() : super(const ServerPrefsState()) {
    _load();
  }

  SharedPreferences? _prefs;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    if (!mounted) return;
    final raw = prefs.getString(_kProtocolKey);
    var persisted = const <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        persisted = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    // Don't clobber a selection/protocol the user set BEFORE prefs resolved at
    // startup: in-memory values win over the persisted snapshot.
    state = ServerPrefsState(
      selected: state.selected ?? prefs.getString(_kSelectedKey),
      protocol: {...persisted, ...state.protocol},
    );
  }

  Future<void> setSelected(String code) async {
    state = state.copyWith(selected: code);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kSelectedKey, code);
  }

  Future<void> setProtocol(String code, String proto) async {
    final next = Map<String, String>.from(state.protocol)..[code] = proto;
    state = state.copyWith(protocol: next);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kProtocolKey, jsonEncode(next));
  }
}

final serverPrefsProvider =
    StateNotifierProvider<ServerPrefs, ServerPrefsState>((ref) => ServerPrefs());
