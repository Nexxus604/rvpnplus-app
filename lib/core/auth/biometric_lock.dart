// Optional biometric app-lock (fingerprint / Face ID).
//
// The login session itself is long-lived (the refresh token lasts a year and
// rotates) — "log in once and forget". This adds an *optional* lock on top:
// when enabled, the app re-locks every time it goes to the background and
// requires a biometric (or device-PIN fallback) to reopen. Logout stays a
// deliberate action in Account → "Выйти".

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBiometricEnabledKey = 'biometric_lock_enabled';

class BiometricState {
  final bool enabled;
  final bool unlocked;
  const BiometricState({required this.enabled, required this.unlocked});

  BiometricState copyWith({bool? enabled, bool? unlocked}) => BiometricState(
        enabled: enabled ?? this.enabled,
        unlocked: unlocked ?? this.unlocked,
      );
}

class BiometricLock extends Notifier<BiometricState> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _prompting = false;

  @override
  BiometricState build() {
    _load();
    // Start unlocked; if the persisted pref says enabled, _load re-locks.
    return const BiometricState(enabled: false, unlocked: true);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kBiometricEnabledKey) ?? false;
    // Cold start: locked when enabled.
    state = BiometricState(enabled: enabled, unlocked: !enabled);
  }

  /// Whether the device can do biometric / device-credential auth.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticate(String reason) async {
    if (_prompting) return false;
    _prompting = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // Default biometricOnly=false allows the device PIN/pattern fallback
        // so a user without a fingerprint enrolled can still use the lock.
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    } finally {
      _prompting = false;
    }
  }

  /// Turn the lock on (requires one successful auth to confirm). Returns
  /// false if unavailable or the user cancelled.
  Future<bool> enable() async {
    if (!await isAvailable()) return false;
    final ok = await _authenticate('Подтвердите, чтобы включить вход по биометрии');
    if (!ok) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabledKey, true);
    state = const BiometricState(enabled: true, unlocked: true);
    return true;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabledKey, false);
    state = const BiometricState(enabled: false, unlocked: true);
  }

  /// Re-lock — called when the app is backgrounded.
  void lock() {
    if (state.enabled && state.unlocked) {
      state = state.copyWith(unlocked: false);
    }
  }

  /// Prompt the user to unlock. No-op if disabled / already unlocked / a
  /// prompt is already showing.
  Future<void> unlock() async {
    if (!state.enabled || state.unlocked || _prompting) return;
    final ok = await _authenticate('Разблокируйте R-VPN+');
    if (ok) state = state.copyWith(unlocked: true);
  }
}

final biometricLockProvider =
    NotifierProvider<BiometricLock, BiometricState>(BiometricLock.new);

/// Wraps the whole app: shows a lock screen over everything while the
/// biometric lock is engaged. Re-locks when the app is backgrounded.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeUnlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final n = ref.read(biometricLockProvider.notifier);
    // Re-lock only on a full pause/hide — NOT on `inactive`, which also fires
    // while the system biometric sheet is up (that would loop the prompt).
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      n.lock();
    } else if (s == AppLifecycleState.resumed) {
      _maybeUnlock();
    }
  }

  Future<void> _maybeUnlock() async {
    final st = ref.read(biometricLockProvider);
    if (st.enabled && !st.unlocked) {
      await ref.read(biometricLockProvider.notifier).unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(biometricLockProvider);
    final locked = st.enabled && !st.unlocked;
    return Stack(
      children: [
        widget.child,
        if (locked) _LockScreen(onUnlock: _maybeUnlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Cosmic.deepest,
      child: CosmicBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint_rounded, size: 72, color: Cosmic.violetBright),
              const SizedBox(height: 16),
              const Text(
                'R-VPN+ заблокирован',
                style: TextStyle(color: Cosmic.text, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Разблокируйте по отпечатку или Face ID',
                style: TextStyle(color: Cosmic.text2),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Разблокировать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
