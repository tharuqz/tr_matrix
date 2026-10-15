import 'dart:async';

import 'package:uuid/uuid.dart';

import 'offline_store.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Port of the chat-list + chat-view queries from the website.
class ChatRepository {
  final SupabaseClient db;
  final OfflineStore store;
  final String ownerId;
  final _changes = StreamController<String>.broadcast();
  final _refreshing = <String>{};
  final Map<String, String> drafts = {};
  final Map<String, Map<String, dynamic>> _details = {};
  late final OutboxWorker _worker;
  Timer? _retry;
  bool _disposed = false;
  bool offline = false;
  String get _me => ownerId;
  Stream<String> get changes => _changes.stream;
  bool get _current => !_disposed && db.auth.currentUser?.id == ownerId;
  ChatRepository(this.db, this.store, this.ownerId) {
    _worker = OutboxWorker(
      store,
      (row) async {
        final existing = await db
            .from('messages')
            .select(Message.columns)
            .eq('id', row['id'])
            .maybeSingle()
            .timeout(const Duration(seconds: 12));
        if (existing != null) return Map<String, dynamic>.from(existing);
        final sent = await db
            .from('messages')
            .insert(row)
            .select(Message.columns)
            .single()
            .timeout(const Duration(seconds: 12));
        return Map<String, dynamic>.from(sent);
      },
      () {
        offline = false;
        _emit('*');
        unawaited(refreshChats());
      },
    );
    _retry = Timer.periodic(const Duration(seconds: 12), (_) => retryPending());
    unawaited(retryPending());
  }
  void _emit(String key) {
    if (_current && !_changes.isClosed) _changes.add(key);
  }

  Future<void> retryPending() async {
    if (!_current) return;
    try {
      await store.open(ownerId);
      await _worker.flush(ownerId, isCurrentUser: () => _current);
    } catch (_) {
      offline = true;
    }
    if (store.rows(ownerId, 'outbox').isNotEmpty) {
      offline = true;
      _emit('*');
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    unawaited(_changes.close());
  }

  List<Message> cachedMessages(String chatId) =>
      store.messages(ownerId, chatId).map(Message.fromJson).toList();
  List<ChatItem> get cachedChats {
    final items = store.rows(ownerId, 'chats').map(ChatItem.fromJson).toList();
    return items.map((item) {
      final pending = store
          .rows(ownerId, 'outbox')
          .where((r) => r['chat_id'] == item.id)
          .toList();
      if (pending.isEmpty) return item;
      return ChatItem.fromJson({
        ...item.toJson(),
        'preview': pending.last['content'],
        'last_message_at': pending.last['created_at'],
      });
    }).toList()..sort(
      (a, b) => (b.lastMessageAt ?? DateTime(1970)).compareTo(
        a.lastMessageAt ?? DateTime(1970),
      ),
    );
  }

  Future<List<ChatItem>> loadChats() async {
    await store.open(ownerId);
    if (store.has(ownerId, 'chats')) {
      unawaited(refreshChats());
      return cachedChats;
    }
    await refreshChats();
    return cachedChats;
  }

  Future<void> refreshChats() async {
    if (!_current || !_refreshing.add('chats')) return;
    try {
      final items = await _fetchChats().timeout(const Duration(seconds: 12));
      if (!_current) return;
      await store.save(ownerId, 'chats', items.map((i) => i.toJson()).toList());
      offline = false;
    } catch (_) {
      offline = true;
    } finally {
      _refreshing.remove('chats');
      _emit('chats');
    }
  }

  Future<List<Message>> loadMessages(String chatId) async {
    await store.open(ownerId);
    if (store.has(ownerId, 'messages:$chatId')) {
      unawaited(refreshMessages(chatId));
      return cachedMessages(chatId);
    }
    await refreshMessages(chatId);
    return cachedMessages(chatId);
  }

  Future<void> refreshMessages(String chatId) async {
    final key = 'messages:$chatId';
    if (!_current || !_refreshing.add(key)) return;
    try {
      final rows = await _fetchMessages(chatId)
          .timeout(const Duration(seconds: 12));
      if (!_current) return;
      await store.save(ownerId, key, rows);
      for (final row in rows) {
        await store.acknowledge(ownerId, row['id'] as String);
      }
      offline = false;
    } catch (_) {
      offline = true;
    } finally {
      _refreshing.remove(key);
      _emit(chatId);
    }
  }

  Future<void> rememberMessage(Message message) async {
    if (!_current) return;
    try {
      await store.upsertMessage(ownerId, messageJson(message));
    } catch (_) {
      return;
    }
    _emit(message.chatId);
  }

  static Map<String, dynamic> messageJson(Message m) => {
    'id': m.id,
    'chat_id': m.chatId,
    'sender_id': m.senderId,
    'content': m.content,
    'media_url': m.mediaUrl,
    'media_type': m.mediaType,
    'media_name': m.mediaName,
    'media_size': m.mediaSize,
    'created_at': m.createdAt.toUtc().toIso8601String(),
    'deleted': m.deleted,
    'edited': m.edited,
    'reply_to_id': m.replyToId,
    'pending': m.pending,
  };
  Future<Map<String, dynamic>?> loadChatDetails(String chatId) async {
    await store.open(ownerId);
    final key = 'details:$chatId';
    final cached = store.rows(ownerId, key);
    Future<Map<String, dynamic>?> fetch() async {
      try {
        final row = await db
            .from('chats')
            .select(
              'id, is_group, title, avatar_url, wallpaper_url, created_by, user_a, user_b',
            )
            .eq('id', chatId)
            .maybeSingle()
            .timeout(const Duration(seconds: 12));
        if (_current && row != null) {
          _details[chatId] = row;
          await store.save(ownerId, key, [row]);
        }
        return row;
      } catch (_) {
        return _details[chatId];
      }
    }

    if (cached.isNotEmpty) {
      unawaited(fetch());
      return cached.first;
    }
    return fetch();
  }

  static const _chatCols =
      'id, user_a, user_b, last_message_at, is_group, title, avatar_url';

  Future<List<ChatItem>> _fetchChats() async {
    final me = _me;
    final results = await Future.wait([
      db.from('chats').select(_chatCols).or('user_a.eq.$me,user_b.eq.$me'),
      db.from('chat_members').select('chat_id').eq('user_id', me),
      db
          .from('chat_state')
          .select('chat_id, hidden, cleared_at')
          .eq('user_id', me),
    ]);
    final dm = List<Map<String, dynamic>>.from(results[0]);
    final memberIds = List<Map<String, dynamic>>.from(results[1])
        .map((r) => r['chat_id'] as String)
        .toList();
    final states = {
      for (final s in List<Map<String, dynamic>>.from(results[2]))
        s['chat_id'] as String: s,
    };

    var groups = <Map<String, dynamic>>[];
    if (memberIds.isNotEmpty) {
      groups = List<Map<String, dynamic>>.from(
        await db.from('chats').select(_chatCols).inFilter('id', memberIds),
      );
    }

    final seen = <String>{};
    final rows =
        [...dm, ...groups].where((c) => seen.add(c['id'] as String)).toList()
          ..removeWhere((c) => states[c['id']]?['hidden'] == true);
    rows.sort(
      (a, b) => _ts(b['last_message_at']).compareTo(_ts(a['last_message_at'])),
    );
    if (rows.isEmpty) return [];

    // Optional mute/archive flags.
    final flags = <String, Map<String, dynamic>>{};
    try {
      final extra = await db
          .from('chat_state')
          .select('chat_id, archived, muted_until')
          .eq('user_id', me);
      for (final r in List<Map<String, dynamic>>.from(extra)) {
        flags[r['chat_id'] as String] = r;
      }
    } catch (_) {}

    final otherIds = rows
        .where((c) => c['is_group'] != true)
        .map((c) => c['user_a'] == me ? c['user_b'] : c['user_a'])
        .whereType<String>()
        .toList();
    final profiles = <String, Profile>{};
    if (otherIds.isNotEmpty) {
      final ps = await db
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_admin')
          .inFilter('id', otherIds);
      for (final p in List<Map<String, dynamic>>.from(ps)) {
        profiles[p['id'] as String] = Profile.fromJson(p);
      }
    }

    final items = await Future.wait(
      rows.map((c) async {
        final id = c['id'] as String;
        final cleared = states[id]?['cleared_at'] as String?;
        var q = db
            .from('messages')
            .select('content, media_type, media_name, deleted')
            .eq('chat_id', id);
        if (cleared != null) q = q.gt('created_at', cleared);
        final last = List<Map<String, dynamic>>.from(
          await q.order('created_at', ascending: false).limit(1),
        );
        String preview = '';
        if (last.isNotEmpty) {
          final m = last.first;
          if (m['deleted'] == true) {
            preview = 'Message deleted';
          } else if ((m['content'] as String?)?.isNotEmpty == true) {
            preview = m['content'] as String;
          } else if (RegExp(r'^trmx-sticker-')
              .hasMatch((m['media_name'] as String?) ?? '')) {
            preview = 'Sticker';
          } else if ((m['media_type'] as String?)?.startsWith('audio/') ==
              true) {
            preview = '🎤 Voice note';
          } else if ((m['media_type'] as String?)?.startsWith('image/') ==
              true) {
            preview = '📷 Photo';
          } else if (m['media_type'] != null) {
            preview = '📎 File';
          }
        }
        final unread = await _unread(id, cleared);
        final f = flags[id];
        final muteUntil = f?['muted_until'] as String?;
        final muted =
            muteUntil != null &&
            DateTime.parse(muteUntil).isAfter(DateTime.now());

        if (c['is_group'] == true) {
          return ChatItem(
            id: id,
            isGroup: true,
            title: (c['title'] ?? 'Group') as String,
            avatarUrl: c['avatar_url'] as String?,
            preview: preview,
            lastMessageAt: _dt(c['last_message_at']),
            unread: unread,
            archived: f?['archived'] == true,
            muted: muted,
          );
        }
        final other = c['user_a'] == me
            ? c['user_b'] as String?
            : c['user_a'] as String?;
        final p = other == null ? null : profiles[other];
        return ChatItem(
          id: id,
          isGroup: false,
          title: p?.displayName ?? 'Unknown',
          avatarUrl: p?.avatarUrl,
          otherUserId: other,
          preview: preview,
          lastMessageAt: _dt(c['last_message_at']),
          unread: unread,
          archived: f?['archived'] == true,
          muted: muted,
        );
      }),
    );
    return items;
  }

  Future<int> _unread(String chatId, String? cleared) async {
    var q = db
        .from('messages')
        .select('id')
        .eq('chat_id', chatId)
        .neq('sender_id', _me);
    if (cleared != null) q = q.gt('created_at', cleared);
    final incoming = List<Map<String, dynamic>>.from(
      await q.order('created_at', ascending: false).limit(99),
    );
    if (incoming.isEmpty) return 0;
    final ids = incoming.map((m) => m['id'] as String).toList();
    final reads = List<Map<String, dynamic>>.from(
      await db
          .from('message_receipts')
          .select('message_id, read_at')
          .eq('user_id', _me)
          .inFilter('message_id', ids),
    );
    final readIds = reads
        .where((r) => r['read_at'] != null)
        .map((r) => r['message_id'])
        .toSet();
    return ids.where((i) => !readIds.contains(i)).length;
  }

  Future<List<Map<String, dynamic>>> _fetchMessages(String chatId) async {
    final st = await db
        .from('chat_state')
        .select('cleared_at')
        .eq('user_id', _me)
        .eq('chat_id', chatId)
        .maybeSingle();
    var q = db.from('messages').select(Message.columns).eq('chat_id', chatId);
    final cleared = st?['cleared_at'] as String?;
    if (cleared != null) q = q.gt('created_at', cleared);
    final rows = await q.order('created_at', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(rows).reversed.toList();
  }

  Future<Message> sendText(
    String chatId,
    String text, {
    String? replyToId,
  }) async {
    if (!_current) throw StateError('Sign in before sending');
    final row = <String, dynamic>{
      'id': const Uuid().v4(),
      'chat_id': chatId,
      'sender_id': ownerId,
      'content': text,
      'reply_to_id': replyToId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await store.queue(ownerId, row);
    _emit(chatId);
    _emit('chats');
    unawaited(retryPending());
    return Message.fromJson({...row, 'pending': true});
  }

  /// Marks incoming messages as read (feeds unread counters + seen receipts).
  Future<void> markRead(List<Message> msgs) async {
    final ids = msgs
        .where((m) => m.senderId != _me && !m.pending)
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await db
          .from('message_receipts')
          .upsert(
            ids
                .map(
                  (id) => {
                    'message_id': id,
                    'user_id': _me,
                    'read_at': now,
                    'delivered_at': now,
                  },
                )
                .toList(),
            onConflict: 'message_id,user_id',
          );
    } catch (_) {}
  }

  /// Realtime new messages in one chat.
  RealtimeChannel subscribeMessages(
    String chatId,
    void Function(Message) onInsert,
  ) {
    return db
        .channel('chat:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (p) => onInsert(Message.fromJson(p.newRecord)),
        )
        .subscribe();
  }

  /// Any message change → refresh chat list.
  RealtimeChannel subscribeAll(void Function() onChange) {
    return db
        .channel('chatlist:$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Find or create a 1:1 chat with another user.
  Future<String> getOrCreateDirect(String otherId) async {
    final me = _me;
    final existing = await db
        .from('chats')
        .select('id')
        .or(
          'and(user_a.eq.$me,user_b.eq.$otherId),and(user_a.eq.$otherId,user_b.eq.$me)',
        )
        .maybeSingle();
    if (existing != null) return existing['id'] as String;
    final row = await db
        .from('chats')
        .insert({'user_a': me, 'user_b': otherId})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static int _ts(dynamic v) =>
      v == null ? 0 : DateTime.parse(v as String).millisecondsSinceEpoch;
  static DateTime? _dt(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}
