import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Port of `docs/NATIVE-API.md` `presence:online` — Supabase Presence on
/// channel `presence:online`, track `{ online_at }`, sync/join/leave,
/// plus `touch_last_seen()` every 45s and on resume.
class PresenceService with WidgetsBindingObserver {
  PresenceService(this._db, this._userId);
  final SupabaseClient _db;
  final String _userId;
  RealtimeChannel? _ch;
  Timer? _touchTimer;
  final _ctrl = StreamController<Set<String>>.broadcast();
  Set<String> _online = {};
  final _lastSeen = <String, DateTime>{};
  Stream<Set<String>> get stream => _ctrl.stream;
  Set<String> get online => Set.unmodifiable(_online);
  DateTime? lastSeenAt(String u) => _lastSeen[u];
  bool isOnline(String u) => _online.contains(u);
  Future<void> connect() async {
    WidgetsBinding.instance.addObserver(this);
    _ch = _db.channel('presence:online');
    _ch!
      ..onPresenceSync((_) => _sync())
      ..onPresenceJoin((_) => _sync())
      ..onPresenceLeave((_) => _sync());
    _ch!.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await _ch!.track({
            'online_at': DateTime.now().toUtc().toIso8601String(),
            'user_id': _userId,
          });
        } catch (_) {}
        _touch();
        _touchTimer?.cancel();
        _touchTimer = Timer.periodic(
          const Duration(seconds: 45),
          (_) => _touch(),
        );
      }
    });
  }

  void _sync() {
    try {
      final dynamic state = _ch!.presenceState();
      final next = <String>{};
      if (state is Map) {
        for (final e in (state as Map).entries) {
          final k = e.key.toString();
          if (k.isNotEmpty) next.add(k);
          final v = e.value;
          final list = v is List ? v : [v];
          for (final p in list) {
            try {
              final payload = (p as dynamic).payload as Map?;
              final uid = payload?['user_id']?.toString();
              if (uid != null && uid.isNotEmpty) next.add(uid);
            } catch (_) {}
          }
        }
      }
      _online = next;
      final now = DateTime.now();
      for (final id in next) _lastSeen[id] = now;
      if (!_ctrl.isClosed) _ctrl.add(Set.unmodifiable(_online));
    } catch (_) {}
  }

  Future<void> _touch() async {
    try {
      await _db.rpc('touch_last_seen');
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _touch();
      try {
        _ch?.track({
          'online_at': DateTime.now().toUtc().toIso8601String(),
          'user_id': _userId,
        });
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _touchTimer?.cancel();
    try {
      await _ch?.unsubscribe();
    } catch (_) {}
    await _ctrl.close();
  }
}
