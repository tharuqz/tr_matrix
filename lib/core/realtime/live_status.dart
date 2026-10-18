import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-wide online / last-seen + "delivered" marking.
/// Mirrors the website: src/hooks/use-presence.tsx and
/// src/components/chat/delivery-marker.tsx.
class LiveStatus extends ChangeNotifier with WidgetsBindingObserver {
  LiveStatus._();
  static final instance = LiveStatus._();

  SupabaseClient get _db => Supabase.instance.client;
  String? _me;
  RealtimeChannel? _presence, _delivery;
  Timer? _beat, _retry;
  int _attempt = 0;
  Set<String> _online = {};
  final Map<String, DateTime?> _lastSeen = {};
  final Set<String> _delivered = {};

  bool isOnline(String id) => _online.contains(id);
  DateTime? lastSeen(String id) => _lastSeen[id];

  /// Start (or switch account). Pass null on sign-out.
  Future<void> start(String? userId) async {
    if (userId == _me) return;
    await stop();
    _me = userId;
    if (userId == null) return;
    WidgetsBinding.instance.addObserver(this);

    _touch();
    _beat = Timer.periodic(const Duration(seconds: 45), (_) => _touch());

    // Presence key = user id, exactly like the website, so both see each other.
    final ch = _db.channel(
      'presence:online',
      opts: RealtimeChannelConfig(key: userId),
    );
    void sync() {
      try {
        final next = <String>{};
        for (final s in ch.presenceState()) {
          if (s.key.isNotEmpty) next.add(s.key);
        }
        // People who just went offline: remember "now" as last seen.
        for (final id in _online.difference(next)) {
          _lastSeen[id] = DateTime.now();
        }
        _online = next;
        notifyListeners();
      } catch (_) {}
    }

    ch
      ..onPresenceSync((_) => sync())
      ..onPresenceJoin((_) => sync())
      ..onPresenceLeave((_) => sync())
      ..subscribe((status, _) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _attempt = 0;
          try {
            await ch.track({
              'online_at': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (_) {}
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          // Network dropped: without a retry everybody looks offline (or
          // stuck online) until restart. Reconnect with backoff.
          _scheduleRestart();
        }
      });
    _presence = ch;

    // Mark incoming messages delivered while the app is open on any screen.
    _delivery = _db
        .channel('delivery:$userId:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) {
            final id = p.newRecord['id']?.toString();
            if (id != null && p.newRecord['sender_id'] != _me)
              _markDelivered(id);
          },
        )
        .subscribe((s, _) {
      if (s == RealtimeSubscribeStatus.subscribed) _catchUp();
    });
  }

  void _scheduleRestart() {
    final me = _me;
    if (me == null || (_retry?.isActive ?? false)) return;
    _attempt = (_attempt + 1).clamp(1, 6);
    _retry = Timer(Duration(seconds: 2 << _attempt), () async {
      if (_me != me) return;
      final keep = _attempt;
      await stop();
      _attempt = keep;
      await start(me);
    });
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    _retry = null;
    _beat?.cancel();
    _beat = null;
    for (final ch in [_presence, _delivery]) {
      if (ch != null) {
        try {
          await _db.removeChannel(ch);
        } catch (_) {}
      }
    }
    _presence = _delivery = null;
    _online = {};
    _lastSeen.clear();
    _delivered.clear();
    _me = null;
    notifyListeners();
  }

  /// Fetch real last-seen times (friends only) from the server.
  Future<void> loadLastSeen(List<String> ids) async {
    final want = ids.where((i) => i.isNotEmpty).toList();
    if (want.isEmpty) return;
    try {
      final rows = await _db.rpc(
        'get_friend_last_seen',
        params: {'_ids': want},
      );
      for (final r in (rows as List)) {
        final t = DateTime.tryParse(
          r['last_seen_at']?.toString() ?? '',
        )?.toLocal();
        final prev = _lastSeen[r['user_id'].toString()];
        if (t != null && (prev == null || t.isAfter(prev)))
          _lastSeen[r['user_id'].toString()] = t;
      }
    } catch (e) {
      debugPrint('[presence] last seen: $e');
    }
    // Friends-only lookup empty/failed: use the profile time so it never
    // just says "offline".
    final missing = want.where((i) => _lastSeen[i] == null).toList();
    if (missing.isNotEmpty) {
      try {
        final rows = await _db
            .from('profiles')
            .select('id, last_seen_at')
            .inFilter('id', missing);
        for (final r in rows) {
          final t = DateTime.tryParse(r['last_seen_at']?.toString() ?? '')
              ?.toLocal();
          if (t != null) _lastSeen[r['id'].toString()] = t;
        }
      } catch (e) {
        debugPrint('[presence] profile last seen: $e');
      }
    }
    notifyListeners();
  }

  void _touch() => _db.rpc('touch_last_seen').catchError((_) => null);

  void _markDelivered(String id) {
    if (!_delivered.add(id)) return;
    _db.rpc('mark_message_delivered', params: {'_message_id': id}).catchError((
      _,
    ) {
      _delivered.remove(id);
      return null;
    });
  }

  Future<void> _catchUp() async {
    final me = _me;
    if (me == null) return;
    try {
      final since = DateTime.now()
          .subtract(const Duration(days: 7))
          .toUtc()
          .toIso8601String();
      final recent = await _db
          .from('messages')
          .select('id')
          .neq('sender_id', me)
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(200);
      final ids = [
        for (final r in recent) r['id'] as String,
      ].where((i) => !_delivered.contains(i)).toList();
      if (ids.isEmpty) return;
      final have = await _db
          .from('message_receipts')
          .select('message_id')
          .eq('user_id', me)
          .inFilter('message_id', ids);
      final got = {for (final r in have) r['message_id']};
      for (final id in ids) {
        if (got.contains(id)) {
          _delivered.add(id);
        } else {
          _markDelivered(id);
        }
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _touch();
      _catchUp();
      try {
        _presence?.track({
          'online_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}
    } else if (s == AppLifecycleState.paused ||
        s == AppLifecycleState.hidden ||
        s == AppLifecycleState.detached) {
      // hidden = Windows window minimized.
      // Leaving the app: drop out of "online" so others see real last seen.
      _touch();
      try {
        _presence?.untrack();
      } catch (_) {}
    }
  }
}

/// Same wording as the website's formatLastSeen.
String formatLastSeen(DateTime? t) {
  if (t == null) return 'offline';
  final diff = DateTime.now().difference(t);
  final min = diff.inMinutes;
  if (min < 1) return 'last seen just now';
  if (min < 60) return 'last seen ${min}m ago';
  final hr = diff.inHours;
  String p0(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return 'last seen today at ${p0(t.hour)}:${p0(t.minute)}';
  if (day == today.subtract(const Duration(days: 1)))
    return 'last seen yesterday at ${p0(t.hour)}:${p0(t.minute)}';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String p(int n) => n.toString().padLeft(2, '0');
  if (diff.inDays < 7)
    return 'last seen ${wd[t.weekday - 1]} ${p(t.hour)}:${p(t.minute)}';
  return 'last seen ${mo[t.month - 1]} ${t.day}';
}
