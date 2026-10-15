import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

const feedBucket = 'announcement-media';
const feedReactions = ['❤️', '👍', '😂', '😮', '😢', '🎉'];

class FeedAttachment {
  final String path, name, type, kind;
  final int size;
  FeedAttachment(this.path, this.name, this.size, this.type, this.kind);
  factory FeedAttachment.fromJson(Map j) => FeedAttachment(
        j['path'] ?? '',
        j['name'] ?? 'file',
        (j['size'] as num?)?.toInt() ?? 0,
        j['type'] ?? 'application/octet-stream',
        j['kind'] ?? 'file',
      );
  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'size': size, 'type': type, 'kind': kind};
}

class FeedPost {
  final String id, authorId, title, body, visibility;
  final List<FeedAttachment> attachments;
  final List<String> allowedUserIds;
  final DateTime createdAt;
  final DateTime? expiresAt;
  FeedPost.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        authorId = j['author_id'],
        title = j['title'] ?? '',
        body = j['body'] ?? '',
        visibility = j['visibility'] ?? 'friends',
        attachments = [for (final a in (j['attachments'] as List? ?? [])) FeedAttachment.fromJson(a as Map)],
        allowedUserIds = List<String>.from(j['allowed_user_ids'] ?? const []),
        createdAt = DateTime.parse(j['created_at']).toLocal(),
        expiresAt = j['expires_at'] == null ? null : DateTime.parse(j['expires_at']).toLocal();
  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

class FeedComment {
  final String id, userId, body;
  final DateTime createdAt;
  FeedComment.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        userId = j['user_id'],
        body = j['body'] ?? '',
        createdAt = DateTime.parse(j['created_at']).toLocal();
}

class PostExtras {
  final Map<String, String> reactions; // userId -> emoji
  final List<FeedComment> comments;
  final bool commentsEnabled;
  final Map<String, Profile> people;
  PostExtras(this.reactions, this.comments, this.commentsEnabled, this.people);
}

class HiveGroup {
  final String id, title;
  final String? avatarUrl;
  final bool admin;
  HiveGroup(this.id, this.title, this.avatarUrl, this.admin);
}

class HiveActivity {
  final String id, chatId, authorId, kind, title;
  final List<String> items;
  final DateTime? unlockAt, closedAt;
  final String? outcome;
  final DateTime createdAt;
  HiveActivity.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        chatId = j['chat_id'],
        authorId = j['author_id'],
        kind = j['kind'],
        title = j['title'] ?? '',
        items = List<String>.from(j['items'] ?? const []),
        unlockAt = j['unlock_at'] == null ? null : DateTime.parse(j['unlock_at']).toLocal(),
        closedAt = j['closed_at'] == null ? null : DateTime.parse(j['closed_at']).toLocal(),
        outcome = j['outcome'],
        createdAt = DateTime.parse(j['created_at']).toLocal();
  bool get locked => kind == 'capsule' && (unlockAt == null || unlockAt!.isAfter(DateTime.now()));
}

class HiveResponse {
  final String id, activityId, userId, reason;
  final int slot;
  final int? choice;
  final bool done;
  HiveResponse.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        activityId = j['activity_id'],
        userId = j['user_id'],
        reason = j['reason'] ?? '',
        slot = (j['slot'] as num?)?.toInt() ?? 0,
        choice = (j['choice'] as num?)?.toInt(),
        done = j['done'] == true;
}

class HiveBoard {
  final List<HiveActivity> activities;
  final List<HiveResponse> responses;
  final Map<String, String> bodies;
  HiveBoard(this.activities, this.responses, this.bodies);
}

String _rid() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Port of hives-board.tsx, post-interactions.tsx, hive-activities.tsx and lib/hives.ts.
class HivesRepository {
  final SupabaseClient db;
  HivesRepository(this.db);
  String get me => db.auth.currentUser!.id;

  // ---------------- community feed
  Future<bool> postingLocked() async {
    try {
      final r = await db.from('app_settings').select('value').eq('key', 'announcement_lock').maybeSingle();
      return r?['value'] == true;
    } catch (_) {
      return true;
    }
  }

  Future<List<FeedPost>> posts({int limit = 20, bool mine = false}) async {
    var q = db.from('announcements').select();
    if (mine) q = q.eq('author_id', me);
    final rows = await q.order('created_at', ascending: false).order('id', ascending: false).limit(limit);
    return [for (final r in rows) FeedPost.fromJson(r)];
  }

  RealtimeChannel watchPosts(void Function() onChange) => db
      .channel('announcements:all')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'announcements', callback: (_) => onChange())
      .subscribe();

  final Map<String, (String, DateTime)> _signed = {};
  Future<String?> mediaUrl(String path) async {
    final hit = _signed[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    try {
      final u = await db.storage.from(feedBucket).createSignedUrl(path, 3600);
      _signed[path] = (u, DateTime.now().add(const Duration(minutes: 55)));
      return u;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Profile>> profiles(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await db.from('profiles').select('id, username, display_name, avatar_url').inFilter('id', list);
    return {for (final r in rows) r['id'] as String: Profile.fromJson(r)};
  }

  Future<List<Profile>> friends() async {
    final rel = await db
        .from('relationships')
        .select('requester_id, addressee_id')
        .eq('status', 'accepted')
        .or('requester_id.eq.$me,addressee_id.eq.$me');
    final ids = [for (final r in rel) r['requester_id'] == me ? r['addressee_id'] as String : r['requester_id'] as String];
    return (await profiles(ids)).values.toList();
  }

  Future<FeedAttachment> uploadAttachment(String name, Uint8List bytes, String type) async {
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path = '$me/${_rid()}-$safe';
    await db.storage.from(feedBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type, upsert: false));
    final kind = type.startsWith('image/') ? 'image' : (type.startsWith('video/') ? 'video' : 'file');
    return FeedAttachment(path, name, bytes.length, type, kind);
  }

  Future<void> removeFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await db.storage.from(feedBucket).remove(paths);
    } catch (_) {}
  }

  /// Creates or edits a post. Returns the post id.
  Future<String> savePost({
    FeedPost? editing,
    required String body,
    required List<FeedAttachment> attachments,
    required String visibility,
    required List<String> allowed,
    required Duration? duration, // null = never expires (admins only)
  }) async {
    const maxMs = 30 * 86400000;
    final created = editing?.createdAt ?? DateTime.now();
    String? expires;
    if (duration != null) {
      final a = DateTime.now().add(duration).millisecondsSinceEpoch;
      final b = created.millisecondsSinceEpoch + maxMs;
      expires = DateTime.fromMillisecondsSinceEpoch(min(a, b)).toUtc().toIso8601String();
    }
    final firstLine = body.trim().split('\n').first;
    final values = {
      'title': editing?.title.isNotEmpty == true
          ? editing!.title
          : (firstLine.isEmpty ? 'Shared a moment' : firstLine.substring(0, min(140, firstLine.length))),
      'body': body.trim(),
      'attachments': [for (final a in attachments) a.toJson()],
      'visibility': visibility,
      'allowed_user_ids': visibility == 'selected' ? allowed : <String>[],
      'expires_at': expires,
    };
    if (editing != null) {
      await db.from('announcements').update(values).eq('id', editing.id);
      return editing.id;
    }
    final r = await db.from('announcements').insert({'author_id': me, ...values}).select('id').single();
    return r['id'] as String;
  }

  Future<void> deletePost(FeedPost p) async {
    await db.from('announcements').delete().eq('id', p.id);
    await removeFiles([for (final a in p.attachments) a.path]);
  }

  Future<bool> setCommentsEnabled(String postId, bool on) async {
    try {
      await db.from('announcement_settings').upsert({'post_id': postId, 'comments_enabled': on});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<PostExtras> extras(String postId) async {
    final res = await Future.wait<dynamic>([
      db.from('announcement_reactions').select().eq('post_id', postId),
      db.from('announcement_comments').select().eq('post_id', postId).order('created_at', ascending: true).limit(100),
      db.from('announcement_settings').select('comments_enabled').eq('post_id', postId).maybeSingle(),
    ]);
    final reactions = {for (final r in res[0] as List) r['user_id'] as String: r['emoji'] as String};
    final comments = [for (final c in res[1] as List) FeedComment.fromJson(Map<String, dynamic>.from(c))];
    final setting = res[2] as Map<String, dynamic>?;
    final people = await profiles([...reactions.keys, ...comments.map((c) => c.userId)]);
    return PostExtras(reactions, comments, setting?['comments_enabled'] ?? true, people);
  }

  Future<void> react(String postId, String? emoji) => emoji == null
      ? db.from('announcement_reactions').delete().eq('post_id', postId).eq('user_id', me)
      : db.from('announcement_reactions').upsert({'post_id': postId, 'user_id': me, 'emoji': emoji});

  Future<void> comment(String postId, String body) =>
      db.from('announcement_comments').insert({'post_id': postId, 'user_id': me, 'body': body.trim()});

  Future<void> deleteComment(String id) => db.from('announcement_comments').delete().eq('id', id);

  // ---------------- my Hives (groups) + activities
  Future<List<HiveGroup>> myHives() async {
    final members = await db.from('chat_members').select('chat_id, role').eq('user_id', me);
    if (members.isEmpty) return [];
    final roles = {for (final m in members) m['chat_id'] as String: m['role'] as String?};
    final chats = await db
        .from('chats')
        .select('id, title, avatar_url, last_message_at')
        .eq('is_group', true)
        .inFilter('id', roles.keys.toList())
        .order('last_message_at', ascending: false, nullsFirst: false);
    return [for (final c in chats) HiveGroup(c['id'], c['title'] ?? 'Hive', c['avatar_url'], roles[c['id']] == 'admin')];
  }

  Future<HiveBoard> board(String chatId) async {
    final rows = await db.from('hive_activities').select().eq('chat_id', chatId).order('created_at', ascending: false);
    final acts = [for (final r in rows) HiveActivity.fromJson(r)];
    if (acts.isEmpty) return HiveBoard([], [], {});
    final ids = acts.map((a) => a.id).toList();
    final res = await Future.wait([
      db.from('hive_responses').select().inFilter('activity_id', ids),
      db.from('hive_bodies').select().inFilter('activity_id', ids),
    ]);
    return HiveBoard(
      acts,
      [for (final r in res[0]) HiveResponse.fromJson(r)],
      {for (final b in res[1]) b['activity_id'] as String: (b['body'] ?? '') as String},
    );
  }

  static List<String> parseItems(String v) => v.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  static String? validate(String kind, String title, String body, List<String> items, DateTime? unlock) {
    if (title.trim().isEmpty || title.trim().length > 140) return 'Add a title (up to 140 characters).';
    if (body.length > 10000) return 'Message is too long.';
    if ((kind == 'capsule' || kind == 'catchup') && body.trim().isEmpty) return 'Add a message.';
    if (kind == 'capsule' && (unlock == null || !unlock.isAfter(DateTime.now()))) return 'Choose a future unlock time.';
    if (kind == 'decision' || kind == 'mission') {
      final minItems = kind == 'decision' ? 2 : 1;
      if (items.length < minItems || items.length > 20 || items.any((x) => x.length > 200) || items.toSet().length != items.length) {
        return 'Add distinct options or tasks (up to 20).';
      }
    }
    return null;
  }

  Future<void> createActivity(String chatId, String kind, String title, String body, List<String> items, DateTime? unlock) =>
      db.rpc('create_hive_activity', params: {
        '_chat_id': chatId,
        '_kind': kind,
        '_title': title.trim(),
        '_body': body,
        '_items': kind == 'decision' || kind == 'mission' ? items : <String>[],
        '_unlock_at': kind == 'capsule' ? unlock!.toUtc().toIso8601String() : null,
      });

  Future<void> respond(String id, int slot, String action, String reason) =>
      db.rpc('respond_hive_activity', params: {'_id': id, '_slot': slot, '_action': action, '_reason': reason});

  Future<void> closeDecision(String id, String outcome) =>
      db.rpc('close_hive_decision', params: {'_id': id, '_outcome': outcome});
}
