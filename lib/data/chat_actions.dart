import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_repository.dart';
import 'models.dart';

const chatBucket = 'chat-media';
const wallpaperBucket = 'wallpapers';
const quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Sticker files are normal chat files with this exact name pattern (same as the website).
bool isStickerName(String? n) =>
    RegExp(r'^trmx-sticker-[a-f0-9]{64}\.(png|gif)$').hasMatch(n ?? '');

class GroupMember {
  final Profile profile;
  final bool admin;
  GroupMember(this.profile, this.admin);
}

/// Part 2 features: files, voice, stickers, reactions, edit/delete, groups, wallpaper.
extension ChatActions on ChatRepository {
  String get me => db.auth.currentUser!.id;

  // ---------- Files ----------
  Future<String> uploadMedia(
    String chatId,
    String name,
    Uint8List bytes,
    String mime,
  ) async {
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final rnd = List.generate(
      12,
      (_) => Random().nextInt(16).toRadixString(16),
    ).join();
    final path =
        '$chatId/$me/${DateTime.now().millisecondsSinceEpoch}-$rnd-$safe';
    final bucket = db.storage.from(chatBucket);
    final signed = await bucket.createSignedUploadUrl(path);
    await bucket.uploadBinaryToSignedUrl(
      path,
      signed.token,
      bytes,
      FileOptions(contentType: mime.split(';').first.trim(), upsert: true),
    );
    return path;
  }

  Future<Message> sendMedia(
    String chatId, {
    required String name,
    required Uint8List bytes,
    required String mime,
    String? caption,
    String? replyToId,
  }) async {
    final path = await uploadMedia(chatId, name, bytes, mime);
    final row = await db
        .from('messages')
        .insert({
          'chat_id': chatId,
          'sender_id': me,
          'content': (caption?.trim().isEmpty ?? true) ? null : caption!.trim(),
          'media_url': path,
          'media_type': mime.split(';').first.trim(),
          'media_name': name,
          'media_size': bytes.length,
          'reply_to_id': replyToId,
        })
        .select(Message.columns)
        .single();
    final message = Message.fromJson(row);
    await rememberMessage(message);
    return message;
  }

  static final _urlCache = <String, (String, DateTime)>{};
  Future<String?> mediaUrl(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('p2p://')) return null;
    if (path.startsWith('http')) return path;
    final hit = _urlCache[path];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    try {
      final url = await db.storage.from(chatBucket).createSignedUrl(path, 3600);
      _urlCache[path] = (url, DateTime.now().add(const Duration(minutes: 50)));
      return url;
    } catch (_) {
      return null;
    }
  }

  // ---------- Edit / delete ----------
  Future<void> editMessage(String id, String text) => db
      .from('messages')
      .update({'content': text, 'edited': true})
      .eq('id', id);

  Future<void> deleteForEveryone(String id) => db
      .from('messages')
      .update({
        'deleted': true,
        'content': null,
        'media_url': null,
        'media_name': null,
        'media_size': null,
        'media_type': null,
      })
      .eq('id', id);

  // ---------- Reactions ----------
  /// messageId -> list of emojis, plus my own emoji per message.
  Future<(Map<String, List<String>>, Map<String, String>)> loadReactions(
    String chatId,
  ) async {
    final all = <String, List<String>>{}, mine = <String, String>{};
    try {
      final rows = await db
          .from('message_reactions')
          .select('message_id, emoji, user_id')
          .eq('chat_id', chatId);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final id = r['message_id'] as String;
        (all[id] ??= []).add(r['emoji'] as String);
        if (r['user_id'] == me) mine[id] = r['emoji'] as String;
      }
    } catch (_) {}
    return (all, mine);
  }

  Future<void> setReaction(
    String chatId,
    String messageId,
    String? emoji,
  ) async {
    if (emoji == null) {
      await db
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', me);
    } else {
      await db.from('message_reactions').upsert({
        'chat_id': chatId,
        'message_id': messageId,
        'user_id': me,
        'emoji': emoji,
      }, onConflict: 'message_id,user_id');
    }
  }

  /// Inserts, edits, deletes and reaction changes for one chat.
  RealtimeChannel subscribeChat(
    String chatId, {
    required void Function(Message) onUpsert,
    required void Function() onReactions,
  }) {
    final f = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'chat_id',
      value: chatId,
    );
    return db
        .channel('chat2:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: f,
          callback: (p) {
            final m = Message.fromJson(p.newRecord);
            rememberMessage(m);
            onUpsert(m);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: f,
          callback: (p) {
            final m = Message.fromJson(p.newRecord);
            rememberMessage(m);
            onUpsert(m);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          filter: f,
          callback: (_) => onReactions(),
        )
        .subscribe();
  }

  // ---------- Chat details ----------
  Future<Map<String, dynamic>?> chatRow(String chatId) =>
      loadChatDetails(chatId);

  // ---------- Groups ----------
  Future<String> createGroup(String title, List<String> memberIds) async {
    final id = await db.rpc(
      'create_group_chat',
      params: {'_title': title, '_member_ids': memberIds},
    );
    return id as String;
  }

  Future<List<GroupMember>> groupMembers(String chatId) async {
    final rows = List<Map<String, dynamic>>.from(
      await db
          .from('chat_members')
          .select('user_id, role')
          .eq('chat_id', chatId),
    );
    if (rows.isEmpty) return [];
    final ps = List<Map<String, dynamic>>.from(
      await db
          .from('profiles')
          .select('id, username, display_name, avatar_url, is_admin')
          .inFilter('id', rows.map((r) => r['user_id']).toList()),
    );
    final byId = {for (final p in ps) p['id'] as String: Profile.fromJson(p)};
    return rows
        .where((r) => byId.containsKey(r['user_id']))
        .map((r) => GroupMember(byId[r['user_id']]!, r['role'] == 'admin'))
        .toList();
  }

  Future<void> addMembers(String chatId, List<String> ids) => db.rpc(
    'add_group_members',
    params: {'_chat_id': chatId, '_member_ids': ids},
  );
  Future<void> removeMember(String chatId, String userId) => db.rpc(
    'remove_group_member',
    params: {'_chat_id': chatId, '_user_id': userId},
  );
  Future<void> leaveGroup(String chatId) =>
      db.rpc('leave_group', params: {'_chat_id': chatId});
  Future<void> updateGroup(String chatId, String title, String? avatarUrl) =>
      db.rpc(
        'update_group',
        params: {
          '_chat_id': chatId,
          '_title': title,
          '_avatar_url': avatarUrl ?? '',
        },
      );

  // ---------- Wallpaper ----------
  Future<String> uploadWallpaper(
    String chatId,
    String name,
    Uint8List bytes,
    String mime,
  ) async {
    final ext = name
        .split('.')
        .last
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final path =
        'chats/$chatId/wallpaper-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await db.storage
        .from(wallpaperBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );
    return path;
  }

  Future<void> setWallpaper(String chatId, String? path) =>
      db.rpc('set_chat_wallpaper', params: {'_chat_id': chatId, '_path': path});

  Future<String?> wallpaperUrl(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('preset:')) return null;
    if (path.startsWith('http')) return path;
    try {
      return await db.storage
          .from(wallpaperBucket)
          .createSignedUrl(path, 60 * 60 * 24 * 7);
    } catch (_) {
      return null;
    }
  }
}
