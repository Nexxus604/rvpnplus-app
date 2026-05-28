// Optional biometric / device-credential app-lock (fingerprint, Face ID, or
// the phone's screen-lock PIN/pattern/password = "код доступа").
//
// The login session itself is long-lived (refresh token lasts a year and
// rotates) — "log in once and forget". This adds an *optional* lock on top:
// when enabled, the app re-locks every time it goes to the background and
// requires biometric/device-credential to reopen. Logout stays a deliberate
// action in Account → "Выйти".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBiometricEnabledKey = 'biometric_lock_enabled';

class BiometricState {
  final bool enabled;
  final bool unlocked;
  final String? error;
  const BiometricState({required this.enabled, required this.unlocked, this.error});
}

class BiometricLock extends Notifier<BiometricState> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _prompting = false;

  @override
  BiometricState build() {
    _load();
    return const BiometricState(enabled: false, unlocked: true);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kBiometricEnabledKey) ?? false;
    state = BiometricState(enabled: enabled, unlocked: !enabled);
  }

  // The actual system prompt. Allows the device PIN/pattern/password fallback
  // (biometricOnly: false) so users without an enrolled fingerprint/Face can
  // still unlock with their screen-lock code.
  Future<bool> _auth0(String reason) => _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

  String _humanError(Object e) {
    if (e is PlatformException) {
      switch (e.code) {
        case 'NotAvailable':
          return 'Биометрия/код недоступны. Включите блокировку экрана в настройках телефона.';
        case 'NotEnrolled':
          return 'Не добавлены отпечаток/Face ID/код. Добавьте их в настройках телефона.';
        case 'PasscodeNotSet':
          return 'Не задан код блокировки экрана. Установите PIN/пароль в настройках телефона.';
        case 'LockedOut':
          return 'Слишком много попыток. Подождите немного и попробуйте снова.';
        case 'PermanentlyLockedOut':
          return 'Биометрия временно заблокирована. Разблокируйте телефон кодом, затем повторите.';
        case 'no_fragment_activity':
          return 'Внутренняя ошибка (no_fragment_activity).';
        default:
          return 'Не удалось: ${e.code}${e.message != null ? ' — ${e.message}' : ''}';
      }
    }
    return 'Ошибка: $e';
  }

  /// Turn the lock on — requires one successful auth to confirm. Returns null
  /// on success, or a human-readable error to show the user.
  Future<String?> enable() async {
    if (_prompting) return null;
    _prompting = true;
    try {
      final ok = await _auth0('Подтвердите вход — отпечаток, Face ID или код');
      if (!ok) return 'Не подтверждено. Попробуйте ещё раз.';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBiometricEnabledKey, true);
      state = const BiometricState(enabled: true, unlocked: true);
      return null;
    } catch (e) {
      return _humanError(e);
    } finally {
      _prompting = false;
    }
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabledKey, false);
    state = const BiometricState(enabled: false, unlocked: true);
  }

  /// Re-lock — called when the app is backgrounded.
  void lock() {
    if (state.enabled && state.unlocked) {
      state = BiometricState(enabled: true, unlocked: false);
    }
  }

  /// Prompt the user to unlock. No-op if disabled / already unlocked / a
  /// prompt is already on screen.
  Future<void> unlock() async {
    if (!state.enabled || state.unlocked || _prompting) return;
    _prompting = true;
    try {
      final ok = await _auth0('Разблокируйте R-VPN+');
      if (ok) {
        state = const BiometricState(enabled: true, unlocked: true);
      } else {
        state = const BiometricState(
            enabled: true, unlocked: false, error: 'Не разблокировано. Нажмите «Разблокировать».');
      }
    } catch (e) {
      state = BiometricState(enabled: true, unlocked: false, error: _humanError(e));
    } finally {
      _prompting = false;
    }
  }
}

final biometricLockProvider =
    NotifierProvider<BiometricLock, BiometricState>(BiometricLock.new);

/// Wraps the whole app: shows a lock screen over everything while the lock is
/// engaged, and auto-prompts when it engages or the app resumes.
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
    // while the system auth sheet is up (that would loop the prompt).
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      n.lock();
    } else if (s == AppLifecycleState.resumed) {
      _maybeUnlock();
    }
  }

  void _maybeUnlock() {
    final st = ref.read(biometricLockProvider);
    if (st.enabled && !st.unlocked) {
      ref.read(biometricLockProvider.notifier).unlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-prompt the moment the lock engages (cold-start load, or re-lock).
    ref.listen<BiometricState>(biometricLockProvider, (prev, next) {
      final justLocked = next.enabled && !next.unlocked && (prev == null || prev.unlocked || !prev.enabled);
      if (justLocked) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeUnlock());
    });

    final st = ref.watch(biometricLockProvider);
    final locked = st.enabled && !st.unlocked;
    return Stack(
      children: [
        widget.child,
        if (locked) _LockScreen(error: st.error, onUnlock: _maybeUnlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock, this.error});
  final VoidCallback onUnlock;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Cosmic.deepest,
      child: CosmicBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
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
                  'Разблокируйте отпечатком, Face ID или кодом телефона',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Cosmic.text2),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Cosmic.error, fontSize: 12)),
                ],
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
      ),
    );
  }
}
