import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Port of `src/hooks/use-pinned-chats.ts`.
///
/// Persists pinned chat IDs in SharedPreferences (`trmatrix:pinned_chats:v1`)
/// and exposes a broadcast stream so list panes react instantly across the
/// app (mirrors the web `storage` event). Keeps pinned chats at the top of
/// `cachedChats` across restarts. Falls back to an in-memory set when
/// SharedPreferences is unavailable (offline/test).
class PinnedChatsStore {
  static const key = 'trmatrix:pinned_chats:v1';

  final _controller = StreamController<Set<String>>.broadcast();
  Set<String> _pinned = {};
  bool _loaded = false;

  Stream<Set<String>> get stream => _controller.stream;
  Set<String> get pinned => Set.unmodifiable(_pinned);
  bool isPinned(String chatId) => _pinned.contains(chatId);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        // Stored as JSON array string like '["id1","id2"]'
        final decoded = _decode(raw);
        _pinned = decoded;
      }
    } catch (_) {
      // keep in-memory
    }
    _loaded = true;
    if (!_controller.isClosed) _controller.add(Set.unmodifiable(_pinned));
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = _encode(_pinned);
      await prefs.setString(key, encoded);
    } catch (_) {}
    if (!_controller.isClosed) _controller.add(Set.unmodifiable(_pinned));
  }

  Future<void> toggle(String chatId) async {
    await load();
    if (_pinned.contains(chatId)) {
      _pinned.remove(chatId);
    } else {
      _pinned.add(chatId);
    }
    await _save();
  }

  Future<void> setPinned(String chatId, bool pinned) async {
    await load();
    final changed = pinned ? _pinned.add(chatId) : _pinned.remove(chatId);
    if (changed || _pinned.contains(chatId) == pinned) {
      await _save();
    }
  }

  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }

  static Set<String> _decode(String raw) {
    // Accept both JSON array and comma-separated fallback
    raw = raw.trim();
    if (raw.startsWith('[')) {
      try {
        // naive parse without dart:convert dependency issues: use RegExp
        final ids = RegExp(
          r'"([^"]+)"',
        ).allMatches(raw).map((m) => m.group(1)!).toSet();
        return ids;
      } catch (_) {
        return {};
      }
    }
    if (raw.isEmpty) return {};
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static String _encode(Set<String> ids) {
    final esc = ids.map((id) => '"${id.replaceAll('"', '\\"')}"').join(',');
    return '[$esc]';
  }
}

/// Global singleton so panes and chat views share the same pin set.
final pinnedChatsStore = PinnedChatsStore();
