import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Presence-backed typing indicator per chat. Uses Supabase Realtime
/// presence on channel `typing:<chatId>` so it works with the existing
/// Supabase project without DB migrations. Reuses the singleton Supabase
/// client so build/memory invariants are untouched.
class TypingPresence {
  final SupabaseClient db;
  final String chatId;
  final String userId;
  RealtimeChannel? _ch;
  final _typingUsers = <String, DateTime>{};
  final _ctrl = StreamController<Set<String>>.broadcast();
  Timer? _selfTimer;
  Timer? _prune;

  TypingPresence(this.db, this.chatId, this.userId);

  Stream<Set<String>> get stream => _ctrl.stream;
  Set<String> get current =>
      _typingUsers.keys.where((k) => k != userId).toSet();

  Future<void> connect() async {
    _ch = db.channel('typing:$chatId');
    _ch!.onPresenceSync((_) {
      final dynamic state = _ch!.presenceState();
      final now = DateTime.now();
      _typingUsers.clear();
      if (state is Map) {
        for (final value in state.values) {
          final list = value is List ? value : [value];
          for (final p in list) {
            final payload = (p as dynamic).payload as Map?;
            final uid = payload?['user_id'] as String?;
            if (uid != null && uid != userId) _typingUsers[uid] = now;
          }
        }
      }
      if (!_ctrl.isClosed) _ctrl.add(current);
    });
    _ch!.subscribe((_, __) async {
      try {
        await _ch!.track({'user_id': userId, 'typing': false});
      } catch (_) {}
    });
    _prune = Timer.periodic(const Duration(seconds: 5), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 5));
      _typingUsers.removeWhere((_, t) => t.isBefore(cutoff));
      if (!_ctrl.isClosed) _ctrl.add(current);
    });
  }

  Future<void> setTyping(bool typing) async {
    if (_ch == null) return;
    try {
      await _ch!.track({'user_id': userId, 'typing': typing});
      if (typing) {
        _typingUsers[userId] = DateTime.now();
        _selfTimer?.cancel();
        _selfTimer = Timer(const Duration(seconds: 3), () => setTyping(false));
      }
    } catch (_) {}
  }

  Future<void> dispose() async {
    _selfTimer?.cancel();
    _prune?.cancel();
    try {
      await _ch?.unsubscribe();
    } catch (_) {}
    await _ctrl.close();
  }
}
