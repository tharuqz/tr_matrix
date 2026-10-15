import 'dart:async';
import 'dart:io';

import 'lib/data/offline_store.dart';

void check(bool ok, String rule) {
  if (!ok) throw StateError(rule);
}

Future<void> main() async {
  final disk = <String, String>{};
  OfflineStore fresh() => OfflineStore(
    read: (uid) async => disk[uid],
    write: (uid, value) async {
      if (value == null) {
        disk.remove(uid);
      } else {
        disk[uid] = value;
      }
    },
  );
  var store = fresh();
  await store.open('alice');
  final message = {
    'id': 'uuid-1',
    'chat_id': 'chat-1',
    'sender_id': 'alice',
    'content': 'offline hello',
    'created_at': '2026-10-15T21:25:00Z',
  };
  await store.save('alice', 'chats', [
    {'id': 'chat-1', 'title': 'Friend'},
  ]);
  store = fresh();
  await store.open('alice');
  check(
    store.rows('alice', 'chats').single['title'] == 'Friend',
    'Loaded chats must survive restart',
  );
  await store.queue('alice', message);
  store = fresh();
  await store.open('alice');
  check(
    store.messages('alice', 'chat-1').single['pending'] == true,
    'Offline text must remain pending after restart',
  );
  final failing = OutboxWorker(
    store,
    (_) async => throw StateError('offline'),
    () {},
  );
  await failing.flush('alice', isCurrentUser: () => true);
  check(
    store.rows('alice', 'outbox').length == 1,
    'Failed send must not lose text',
  );
  final remote = <String, Map<String, dynamic>>{};
  final working = OutboxWorker(store, (r) async {
    remote.putIfAbsent(r['id'] as String, () => r);
    return remote[r['id']] ?? r;
  }, () {});
  await working.flush('alice', isCurrentUser: () => true);
  check(
    store.rows('alice', 'outbox').isEmpty && remote.length == 1,
    'Reconnection must deliver and clear pending row',
  );
  await store.queue('alice', message);
  await working.flush('alice', isCurrentUser: () => true);
  check(
    remote.length == 1 && store.messages('alice', 'chat-1').length == 1,
    'Retry must preserve id and avoid duplicate messages',
  );
  await store.open('bob');
  check(
    store.messages('bob', 'chat-1').isEmpty,
    'A different account must not see cached messages',
  );
  await store.clear('alice');
  store = fresh();
  await store.open('alice');
  check(
    store.rows('alice', 'chats').isEmpty,
    'Sign-out cache deletion must persist',
  );
  await Future.wait(
    List.generate(
      20,
      (i) => store.queue('alice', {...message, 'id': 'parallel-$i'}),
    ),
  );
  check(
    store.rows('alice', 'outbox').length == 20,
    'Concurrent offline sends must all persist',
  );
  final unwritable = OfflineStore(
    read: (_) async => null,
    write: (_, __) async => throw StateError('disk full'),
  );
  try {
    await unwritable.queue('alice', message);
  } catch (_) {}
  check(
    unwritable.rows('alice', 'outbox').isEmpty,
    'Failed durable write must not pretend a text was saved',
  );
  final root = await Directory.systemTemp.createTemp('trmatrix-test-');
  try {
    final file = File('${root.path}/cache.json');
    OfflineStore diskStore() => OfflineStore(
      read: (_) async => await file.exists() ? file.readAsString() : null,
      write: (_, value) async {
        if (value == null) {
          await file.delete();
        } else {
          await file.writeAsString(value, flush: true);
        }
      },
    );
    var diskCache = diskStore();
    await diskCache.queue('alice', message);
    diskCache = diskStore();
    await diskCache.open('alice');
    check(
      diskCache.messages('alice', 'chat-1').single['content'] ==
          'offline hello',
      'Text must read back after a disk-backed restart',
    );
    final blocked = Completer<Map<String, dynamic>>();
    var signedIn = true;
    final worker = OutboxWorker(diskCache, (_) => blocked.future, () {});
    final sending = worker.flush('alice', isCurrentUser: () => signedIn);
    signedIn = false;
    blocked.complete(message);
    await sending;
    check(
      diskCache.rows('alice', 'outbox').length == 1,
      'Account switch must not acknowledge an in-flight old-account send',
    );
  } finally {
    await root.delete(recursive: true);
  }
  print('PASS: 11 offline persistence, concurrency, and delivery rules');
}
