import 'models.dart';

import 'chat_repository.dart';

/// Local-only chat flags (pinned/muted/archived) persisted in the encrypted
/// offline cache. Mirrors the web platform’s folders/pinned + mute/archive
/// without requiring a server migration; server state is still synced via
/// refreshChats when available. Keeps build/memory invariants intact.
extension ChatExtras on ChatRepository {
  Future<void> _patchChat(String chatId, Map<String, dynamic> patch) async {
    await store.open(ownerId);
    final rows = store.rows(ownerId, 'chats');
    final idx = rows.indexWhere((r) => r['id'] == chatId);
    if (idx == -1) return;
    final next = {...rows[idx], ...patch};
    rows[idx] = next;
    await store.save(ownerId, 'chats', rows);
  }

  Future<void> togglePin(String chatId) async {
    await store.open(ownerId);
    final rows = store.rows(ownerId, 'chats');
    final idx = rows.indexWhere((r) => r['id'] == chatId);
    if (idx == -1) return;
    final cur = ChatItem.fromJson(rows[idx]);
    await _patchChat(chatId, {'pinned': !cur.pinned});
  }

  /// chat_state model from web: muted_until (far-future = always),
  /// archived, cleared_at (wipe-for-me), hidden. Falls back gracefully
  /// if the DB has not yet had the Phase 5.3b migration applied.
  Future<void> toggleMute(String chatId) async {
    await store.open(ownerId);
    final rows = store.rows(ownerId, 'chats');
    final idx = rows.indexWhere((r) => r['id'] == chatId);
    if (idx == -1) return;
    final cur = ChatItem.fromJson(rows[idx]);
    final next = !cur.muted;
    await _patchChat(chatId, {'muted': next});
    // Mirror to notification guard so pushes are silenced.
    try {
      final when = next ? '9999-12-31T00:00:00Z' : null;
      await db.from('chat_state').upsert({
        'user_id': ownerId,
        'chat_id': chatId,
        'muted_until': when,
      }, onConflict: 'user_id,chat_id');
    } catch (_) {
      try {
        await db.from('chat_state').upsert({
          'user_id': ownerId,
          'chat_id': chatId,
          'muted': next,
        }, onConflict: 'user_id,chat_id');
      } catch (_) {}
    }
  }

  /// Wipe messages for me only (cleared_at). Matches web clearChatForMe.
  Future<void> clearHistory(String chatId) async {
    await store.open(ownerId);
    // Local wipe so the user sees it immediately even offline.
    await store.save(ownerId, 'messages:$chatId', []);
    try {
      await db.from('chat_state').upsert({
        'user_id': ownerId,
        'chat_id': chatId,
        'cleared_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,chat_id');
    } catch (_) {}
    await _patchChat(chatId, {'preview': ''});
  }

  Future<void> toggleArchive(String chatId) async {
    await store.open(ownerId);
    final rows = store.rows(ownerId, 'chats');
    final idx = rows.indexWhere((r) => r['id'] == chatId);
    if (idx == -1) return;
    final cur = ChatItem.fromJson(rows[idx]);
    final next = !cur.archived;
    await _patchChat(chatId, {'archived': next});
    try {
      await db.from('chat_state').upsert({
        'user_id': ownerId,
        'chat_id': chatId,
        'archived': next,
      }, onConflict: 'user_id,chat_id');
    } catch (_) {}
  }

  Future<void> markChatRead(String chatId) async {
    await store.open(ownerId);
    final rows = store.rows(ownerId, 'chats');
    final idx = rows.indexWhere((r) => r['id'] == chatId);
    if (idx == -1) return;
    rows[idx] = {...rows[idx], 'unread': 0};
    await store.save(ownerId, 'chats', rows);
    // mark underlying messages read as well if cached
    final msgs = store.messages(ownerId, chatId);
    if (msgs.isNotEmpty) {
      await markRead(msgs.map(Message.fromJson).toList());
    }
  }

  Future<void> forwardMessage(
    Message src,
    String targetChatId, {
    String? extraText,
  }) async {
    final text = extraText?.trim().isEmpty ?? true
        ? (src.content ?? '')
        : '${src.content ?? ''}\n\n$extraText';
    if (text.trim().isEmpty && src.mediaUrl == null) return;
    if (src.mediaUrl == null) {
      await sendText(targetChatId, text.trim());
      return;
    }
    // For media, create a new message row referencing same storage path
    // (server allows reuse); fallback to text forward if storage not reusable.
    try {
      final row = await db
          .from('messages')
          .insert({
            'chat_id': targetChatId,
            'sender_id': ownerId,
            'content': text.trim().isEmpty ? null : text.trim(),
            'media_url': src.mediaUrl,
            'media_type': src.mediaType,
            'media_name': src.mediaName,
            'media_size': src.mediaSize,
          })
          .select(Message.columns)
          .single();
      await rememberMessage(Message.fromJson(row));
    } catch (_) {
      await sendText(
        targetChatId,
        text.trim().isEmpty
            ? '[Forwarded media: ${src.mediaName ?? src.mediaUrl}]'
            : text.trim(),
      );
    }
  }
}
