import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Port of the chat-list + chat-view queries from the website.
class ChatRepository {
  final SupabaseClient db;
  ChatRepository(this.db);

  String get _me => db.auth.currentUser!.id;
  static const _chatCols = 'id, user_a, user_b, last_message_at, is_group, title, avatar_url';

  Future<List<ChatItem>> loadChats() async {
    final me = _me;
    final results = await Future.wait([
      db.from('chats').select(_chatCols).or('user_a.eq.$me,user_b.eq.$me'),
      db.from('chat_members').select('chat_id').eq('user_id', me),
      db.from('chat_state').select('chat_id, hidden, cleared_at').eq('user_id', me),
    ]);
    final dm = List<Map<String, dynamic>>.from(results[0]);
    final memberIds = List<Map<String, dynamic>>.from(results[1]).map((r) => r['chat_id'] as String).toList();
    final states = {for (final s in List<Map<String, dynamic>>.from(results[2])) s['chat_id'] as String: s};

    var groups = <Map<String, dynamic>>[];
    if (memberIds.isNotEmpty) {
      groups = List<Map<String, dynamic>>.from(await db.from('chats').select(_chatCols).inFilter('id', memberIds));
    }

    final seen = <String>{};
    final rows = [...dm, ...groups].where((c) => seen.add(c['id'] as String)).toList()
      ..removeWhere((c) => states[c['id']]?['hidden'] == true);
    rows.sort((a, b) => _ts(b['last_message_at']).compareTo(_ts(a['last_message_at'])));
    if (rows.isEmpty) return [];

    // Optional mute/archive flags.
    final flags = <String, Map<String, dynamic>>{};
    try {
      final extra = await db.from('chat_state').select('chat_id, archived, muted_until').eq('user_id', me);
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
      final ps = await db.from('profiles').select('id, username, display_name, avatar_url, is_admin').inFilter('id', otherIds);
      for (final p in List<Map<String, dynamic>>.from(ps)) {
        profiles[p['id'] as String] = Profile.fromJson(p);
      }
    }

    final items = await Future.wait(rows.map((c) async {
      final id = c['id'] as String;
      final cleared = states[id]?['cleared_at'] as String?;
      var q = db.from('messages').select('content, media_type, media_name, deleted').eq('chat_id', id);
      if (cleared != null) q = q.gt('created_at', cleared);
      final last = List<Map<String, dynamic>>.from(await q.order('created_at', ascending: false).limit(1));
      String preview = '';
      if (last.isNotEmpty) {
        final m = last.first;
        if (m['deleted'] == true) {
          preview = 'Message deleted';
        } else if ((m['content'] as String?)?.isNotEmpty == true) {
          preview = m['content'] as String;
        } else if (RegExp(r'^trmx-sticker-').hasMatch((m['media_name'] as String?) ?? '')) {
          preview = 'Sticker';
        } else if ((m['media_type'] as String?)?.startsWith('audio/') == true) {
          preview = '🎤 Voice note';
        } else if ((m['media_type'] as String?)?.startsWith('image/') == true) {
          preview = '📷 Photo';
        } else if (m['media_type'] != null) {
          preview = '📎 File';
        }
      }
      final unread = await _unread(id, cleared);
      final f = flags[id];
      final muted = f?['muted_until'] != null && DateTime.parse(f!['muted_until'] as String).isAfter(DateTime.now());

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
      final other = c['user_a'] == me ? c['user_b'] as String? : c['user_a'] as String?;
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
    }));
    return items;
  }

  Future<int> _unread(String chatId, String? cleared) async {
    var q = db.from('messages').select('id').eq('chat_id', chatId).neq('sender_id', _me);
    if (cleared != null) q = q.gt('created_at', cleared);
    final incoming = List<Map<String, dynamic>>.from(await q.order('created_at', ascending: false).limit(99));
    if (incoming.isEmpty) return 0;
    final ids = incoming.map((m) => m['id'] as String).toList();
    final reads = List<Map<String, dynamic>>.from(
      await db.from('message_receipts').select('message_id, read_at').eq('user_id', _me).inFilter('message_id', ids),
    );
    final readIds = reads.where((r) => r['read_at'] != null).map((r) => r['message_id']).toSet();
    return ids.where((i) => !readIds.contains(i)).length;
  }

  Future<List<Message>> loadMessages(String chatId) async {
    final st = await db.from('chat_state').select('cleared_at').eq('user_id', _me).eq('chat_id', chatId).maybeSingle();
    var q = db.from('messages').select(Message.columns).eq('chat_id', chatId);
    final cleared = st?['cleared_at'] as String?;
    if (cleared != null) q = q.gt('created_at', cleared);
    final rows = await q.order('created_at', ascending: true).limit(200);
    return List<Map<String, dynamic>>.from(rows).map(Message.fromJson).toList();
  }

  Future<Message> sendText(String chatId, String text, {String? replyToId}) async {
    final row = await db
        .from('messages')
        .insert({'chat_id': chatId, 'sender_id': _me, 'content': text, 'reply_to_id': replyToId})
        .select(Message.columns)
        .single();
    return Message.fromJson(row);
  }

  /// Marks incoming messages as read (feeds unread counters + seen receipts).
  Future<void> markRead(List<Message> msgs) async {
    final ids = msgs.where((m) => m.senderId != _me && !m.pending).map((m) => m.id).toList();
    if (ids.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await db.from('message_receipts').upsert(
            ids.map((id) => {'message_id': id, 'user_id': _me, 'read_at': now, 'delivered_at': now}).toList(),
            onConflict: 'message_id,user_id',
          );
    } catch (_) {}
  }

  /// Realtime new messages in one chat.
  RealtimeChannel subscribeMessages(String chatId, void Function(Message) onInsert) {
    return db
        .channel('chat:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'chat_id', value: chatId),
          callback: (p) => onInsert(Message.fromJson(p.newRecord)),
        )
        .subscribe();
  }

  /// Any message change → refresh chat list.
  RealtimeChannel subscribeAll(void Function() onChange) {
    return db
        .channel('chatlist:$_me')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'messages', callback: (_) => onChange())
        .subscribe();
  }

  /// Find or create a 1:1 chat with another user.
  Future<String> getOrCreateDirect(String otherId) async {
    final me = _me;
    final existing = await db
        .from('chats')
        .select('id')
        .or('and(user_a.eq.$me,user_b.eq.$otherId),and(user_a.eq.$otherId,user_b.eq.$me)')
        .maybeSingle();
    if (existing != null) return existing['id'] as String;
    final row = await db.from('chats').insert({'user_a': me, 'user_b': otherId}).select('id').single();
    return row['id'] as String;
  }

  static int _ts(dynamic v) => v == null ? 0 : DateTime.parse(v as String).millisecondsSinceEpoch;
  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
}
