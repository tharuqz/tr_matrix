import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local app lock + locked (hidden) chats.
/// Same PIN format as the website (src/components/security/app-lock.tsx):
/// salted SHA-256 of "salt:pin", never synced — each device sets its own.
/// Fingerprint / face unlock is optional and only used if you switch it on.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();
  static final instance = AppLock._();

  static const _key = 'tr-matrix.app-lock.v1';
  static const _chatsKey = 'tr-matrix.locked-chats.v1';

  final _auth = LocalAuthentication();
  SharedPreferences? _p;
  Map<String, dynamic>? _cfg;
  Set<String> _lockedChats = {};
  bool locked = false;
  bool biometricAvailable = false;
  DateTime? _hiddenAt;
  bool _authInProgress = false;

  bool get enabled => _cfg != null;
  int get timeoutMin => (_cfg?['timeoutMin'] as num?)?.toInt() ?? 0;
  int get pinLength => (_cfg?['len'] as num?)?.toInt() ?? 0;
  bool get useBiometric => _cfg?['bio'] == true && biometricAvailable;
  bool get biometricSetting => _cfg?['bio'] == true;
  Set<String> get lockedChats => Set.unmodifiable(_lockedChats);
  bool isChatLocked(String id) => _lockedChats.contains(id);

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    try {
      final raw = _p!.getString(_key);
      _cfg = raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      _cfg = null;
    }
    _lockedChats = (_p!.getStringList(_chatsKey) ?? []).toSet();
    try {
      biometricAvailable = !kIsWeb &&
          await _auth.isDeviceSupported() &&
          (await _auth.canCheckBiometrics ||
              (await _auth.getAvailableBiometrics()).isNotEmpty);
    } catch (_) {
      biometricAvailable = false;
    }
    locked = enabled;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  bool verify(String pin) {
    final c = _cfg;
    if (c == null) return true;
    return _hash(c['salt'] as String, pin) == c['hash'];
  }

  Future<void> setPin(String pin, {int? timeoutMin, bool? bio}) async {
    final r = Random.secure();
    final salt = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _cfg = {
      'salt': salt,
      'hash': _hash(salt, pin),
      'timeoutMin': timeoutMin ?? this.timeoutMin,
      'len': pin.length,
      'bio': bio ?? biometricSetting,
    };
    await _save();
  }

  Future<void> disable() async {
    _cfg = null;
    locked = false;
    await _save();
  }

  Future<void> setTimeout(int min) async {
    if (_cfg == null) return;
    _cfg!['timeoutMin'] = min;
    await _save();
  }

  /// Turning fingerprint on asks for the finger once, so it's really you.
  Future<bool> setBiometric(bool on) async {
    if (_cfg == null) return false;
    if (on &&
        !await authenticateBiometric(
          reason: 'Confirm to use fingerprint unlock',
        )) return false;
    _cfg!['bio'] = on;
    await _save();
    return true;
  }

  Future<void> _save() async {
    final p = _p ??= await SharedPreferences.getInstance();
    if (_cfg == null) {
      await p.remove(_key);
    } else {
      await p.setString(_key, jsonEncode(_cfg));
    }
    notifyListeners();
  }

  void lockNow() {
    if (!enabled) return;
    locked = true;
    notifyListeners();
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  Future<bool> authenticateBiometric({
    String reason = 'Unlock TR MATRIX',
  }) async {
    if (!biometricAvailable || _authInProgress) return false;
    _authInProgress = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('[lock] biometric: $e');
      return false;
    } finally {
      _authInProgress = false;
    }
  }

  // ---- locked chats ----
  Future<void> setChatLocked(String id, bool on) async {
    on ? _lockedChats.add(id) : _lockedChats.remove(id);
    await (_p ??= await SharedPreferences.getInstance()).setStringList(
      _chatsKey,
      _lockedChats.toList(),
    );
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!enabled || _authInProgress) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _hiddenAt ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final at = _hiddenAt;
      _hiddenAt = null;
      if (at != null &&
          DateTime.now().difference(at).inSeconds >= timeoutMin * 60) lockNow();
    }
  }
}
