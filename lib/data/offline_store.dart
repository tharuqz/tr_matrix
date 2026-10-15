import 'dart:async';
import 'dart:convert';

/// Platform-neutral cache/outbox; the device adapter encrypts persistence.
class OfflineStore {
  final Future<String?> Function(String) read;
  final Future<void> Function(String, String?) write;
  final Map<String, Map<String, dynamic>> _users = {};
  final Map<String, Future<void>> _operations = {};
  OfflineStore({required this.read, required this.write});

  Future<void> _serial(String uid, Future<void> Function() action) {
    final previous = _operations[uid] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => action());
    _operations[uid] = next;
    return next;
  }

  Future<void> _open(String uid) async {
    if (_users.containsKey(uid)) return;
    final raw = await read(uid);
    _users[uid] = raw == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> open(String uid) => _serial(uid, () => _open(uid));
  List<Map<String, dynamic>> rows(String uid, String key) =>
      ((_users[uid]?[key] as List?) ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
  bool has(String uid, String key) => _users[uid]?.containsKey(key) ?? false;

  Future<void> _commit(String uid, Map<String, dynamic> next) async {
    // Memory is updated only after durable persistence succeeds.
    await write(uid, jsonEncode(next));
    _users[uid] = next;
  }

  Future<void> save(String uid, String key, List<Map<String, dynamic>> rows) =>
      _serial(uid, () async {
        await _open(uid);
        await _commit(uid, {...?_users[uid], key: rows});
      });
  Future<void> queue(String uid, Map<String, dynamic> row) =>
      _serial(uid, () async {
        await _open(uid);
        final queue = rows(uid, 'outbox')
          ..removeWhere((r) => r['id'] == row['id']);
        queue.add(Map<String, dynamic>.from(row));
        await _commit(uid, {...?_users[uid], 'outbox': queue});
      });
  Future<void> acknowledge(String uid, String id) => _serial(uid, () async {
    await _open(uid);
    final queue = rows(uid, 'outbox');
    if (!queue.any((r) => r['id'] == id)) return;
    queue.removeWhere((r) => r['id'] == id);
    await _commit(uid, {...?_users[uid], 'outbox': queue});
  });
  List<Map<String, dynamic>> messages(String uid, String chatId) {
    final byId = {for (final r in rows(uid, 'messages:$chatId')) r['id']: r};
    for (final r in rows(uid, 'outbox').where((r) => r['chat_id'] == chatId)) {
      byId.putIfAbsent(r['id'], () => {...r, 'pending': true});
    }
    return byId.values.toList()..sort(
      (a, b) =>
          (a['created_at'] as String).compareTo(b['created_at'] as String),
    );
  }

  Future<void> upsertMessage(String uid, Map<String, dynamic> row) =>
      _serial(uid, () async {
        await _open(uid);
        final key = 'messages:${row['chat_id']}';
        final current = rows(uid, key)
          ..removeWhere((r) => r['id'] == row['id']);
        current.add({...row, 'pending': false});
        current.sort(
          (a, b) =>
              (a['created_at'] as String).compareTo(b['created_at'] as String),
        );
        final queue = rows(uid, 'outbox')
          ..removeWhere((r) => r['id'] == row['id']);
        await _commit(uid, {...?_users[uid], key: current, 'outbox': queue});
      });
  Future<void> clear(String uid) => _serial(uid, () async {
    await write(uid, null);
    _users.remove(uid);
  });
}

/// One delivery at a time; failures leave durable pending text untouched.
class OutboxWorker {
  final OfflineStore store;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) deliver;
  final void Function() onChanged;
  bool _busy = false;
  OutboxWorker(this.store, this.deliver, this.onChanged);
  Future<void> flush(
    String uid, {
    required bool Function() isCurrentUser,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      while (isCurrentUser()) {
        final queue = store.rows(uid, 'outbox');
        if (queue.isEmpty) break;
        try {
          final sent = await deliver(queue.first);
          if (!isCurrentUser()) break;
          await store.upsertMessage(uid, sent);
          onChanged();
        } catch (_) {
          break;
        }
      }
    } finally {
      _busy = false;
    }
  }
}
