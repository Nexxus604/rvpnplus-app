import 'package:hooks_riverpod/hooks_riverpod.dart';

/// True while a server switch (disconnect → swap profile → reconnect) is in
/// flight. Guards against rapid re-taps stacking reconnects (which crashed),
/// and lets the main connect button disable itself during the swap window so a
/// concurrent toggle can't race the profile change.
///
/// Lives in its own file so both the home page (writer) and the connect button
/// (reader) can depend on it without a circular import.
final serverSwitchingProvider = StateProvider<bool>((ref) => false);
