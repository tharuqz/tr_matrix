import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models.dart';
import 'pin.dart';

/// Port of hooks/use-auth.tsx.
class AuthService extends ChangeNotifier {
  final SupabaseClient _db;
  StreamSubscription<AuthState>? _sub;

  Session? session;
  Profile? profile;
  bool loading = true;

  AuthService(this._db) {
    session = _db.auth.currentSession;
    if (session != null) {
      _loadProfile(session!.user.id);
    } else {
      loading = false;
    }
    _sub = _db.auth.onAuthStateChange.listen((s) {
      session = s.session;
      if (session != null) {
        _loadProfile(session!.user.id);
      } else {
        profile = null;
        notifyListeners();
      }
    });
  }

  User? get user => session?.user;
  bool get isSignedIn => session != null;
  bool get isAdmin => profile?.isAdmin ?? false;

  static const _select = 'id, username, display_name, avatar_url, bio, is_admin, account_status';

  Future<void> _loadProfile(String uid) async {
    loading = true;
    notifyListeners();
    try {
      final row = await _db.from('profiles').select(_select).eq('id', uid).maybeSingle();
      if (row != null) {
        var p = Profile.fromJson(row);
        if (!p.isAdmin) {
          try {
            final flag = await _db.rpc('current_user_is_admin');
            if (flag == true) p = p.copyWith(isAdmin: true);
          } catch (_) {}
        }
        profile = p;
      }
    } catch (e) {
      debugPrint('[auth] profile load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (user != null) await _loadProfile(user!.id);
  }

  /// Sign in with username + PIN/password (tries every email/password encoding).
  Future<String?> signIn(String username, String secret) async {
    if (!Pin.isValidUsername(username)) return 'Username must be 3–20 letters, numbers or _';
    final pws = Pin.candidatePasswords(secret);
    if (pws.isEmpty) return 'Enter your PIN or password';
    for (final email in Pin.loginEmails(username)) {
      for (final pw in pws) {
        try {
          await _db.auth.signInWithPassword(email: email, password: pw);
          return null;
        } on AuthException catch (_) {
          continue;
        }
      }
    }
    return 'Wrong username or PIN';
  }

  /// Sign up with username + PIN. Profile is created by the backend trigger.
  Future<String?> signUp(String username, String displayName, String pin) async {
    if (!Pin.isValidUsername(username)) return 'Username must be 3–20 letters, numbers or _';
    if (!Pin.isValidPin(pin)) return 'PIN must be 4–6 digits';
    try {
      final res = await _db.auth.signUp(
        email: Pin.pseudoEmail(username),
        password: Pin.padPin(pin),
        data: {'username': Pin.normalize(username), 'display_name': displayName.isEmpty ? username : displayName},
      );
      if (res.session == null) {
        await _db.auth.signInWithPassword(email: Pin.pseudoEmail(username), password: Pin.padPin(pin));
      }
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  /// Runs before sign-out (removes this phone's notification token).
  static Future<void> Function()? beforeSignOut;

  Future<void> signOut() async {
    try {
      await beforeSignOut?.call();
    } catch (_) {}
    await _db.auth.signOut();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
