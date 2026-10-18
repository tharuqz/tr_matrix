import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/chat_extras.dart';
import '../../data/chat_repository.dart';
import '../../data/models.dart';
import '../../core/fancy.dart';
import '../../widgets/common.dart';

/// Website-matching chat actions: delete (for me / for everyone) and block.
/// Same tables and functions as src/lib/chat/actions.ts on the website.
extension ChatManage on ChatRepository {
  /// Hide + clear for me only (the other person keeps the chat).
  Future<void> deleteChatForMe(String chatId) async {
    await db.from('chat_state').upsert({
      'user_id': ownerId,
      'chat_id': chatId,
      'hidden': true,
      'cleared_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,chat_id');
    await _dropLocal(chatId);
  }

  /// Removes the chat and its messages for both people (website delete_chat).
  Future<void> deleteChatForEveryone(String chatId) async {
    await db.rpc('delete_chat', params: {'_chat_id': chatId});
    await _dropLocal(chatId);
  }

  Future<void> _dropLocal(String chatId) async {
    await store.open(ownerId);
    final rows = store.rows(ownerId, 'chats')
      ..removeWhere((r) => r['id'] == chatId);
    await store.save(ownerId, 'chats', rows);
    await store.save(ownerId, 'messages:$chatId', []);
    unawaitedRefresh();
  }

  void unawaitedRefresh() {
    refreshChats();
  }

  Future<bool> isBlocked(String otherId) async {
    final r = await db
        .from('blocked_users')
        .select('id')
        .eq('blocker_id', ownerId)
        .eq('blocked_id', otherId)
        .maybeSingle();
    return r != null;
  }

  Future<void> blockUser(String otherId) async {
    try {
      await db
          .from('blocked_users')
          .insert({'blocker_id': ownerId, 'blocked_id': otherId});
    } catch (e) {
      if (!e.toString().contains('duplicate')) rethrow;
    }
  }

  Future<void> unblockUser(String otherId) => db
      .from('blocked_users')
      .delete()
      .eq('blocker_id', ownerId)
      .eq('blocked_id', otherId);
}

/// Asks "for me" or "for everyone", then deletes. Returns true when deleted.
Future<bool> confirmDeleteChat(BuildContext context, ChatItem item) async {
  final c = context.tr;
  final choice = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: c.surface1,
      title: const Text('Delete chat?'),
      content: Text(
        item.isGroup
            ? 'Delete for me hides this hive and clears its history for you. Only hive admins can delete it for everyone.'
            : 'Delete for me hides the chat and its history for you only. Delete for everyone permanently removes all messages for both of you.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(d, 'me'),
            child: Text('Delete for me', style: TextStyle(color: c.danger))),
        TextButton(
          onPressed: () => Navigator.pop(d, 'all'),
          child: Text('Delete for everyone',
              style: TextStyle(color: c.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  final repo = AppScope.of(context).chats;
  try {
    if (choice == 'all') {
      await repo.deleteChatForEveryone(item.id);
    } else {
      await repo.deleteChatForMe(item.id);
    }
    if (context.mounted) showToast(context, 'Chat deleted');
    return true;
  } catch (_) {
    if (context.mounted) {
      showToast(
        context,
        choice == 'all'
            ? 'Could not delete for everyone (only admins can for hives)'
            : 'Could not delete chat',
        error: true,
      );
    }
    return false;
  }
}

/// Block / unblock the other person in a one-to-one chat.
Future<void> toggleBlock(BuildContext context, ChatItem item) async {
  final other = item.otherUserId;
  if (other == null) return;
  final repo = AppScope.of(context).chats;
  final c = context.tr;
  bool blocked;
  try {
    blocked = await repo.isBlocked(other);
  } catch (_) {
    blocked = false;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: c.surface1,
      title: Text(blocked
          ? 'Unblock ${plainName(item.title)}?'
          : 'Block ${plainName(item.title)}?'),
      content: Text(blocked
          ? 'They will be able to message you again.'
          : 'They will no longer be able to message you.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text(blocked ? 'Unblock' : 'Block',
              style: TextStyle(color: blocked ? context.accent : c.danger)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    blocked ? await repo.unblockUser(other) : await repo.blockUser(other);
    if (context.mounted)
      showToast(context, blocked ? 'User unblocked' : 'User blocked');
  } catch (_) {
    if (context.mounted)
      showToast(context, 'Could not update block', error: true);
  }
}

/// Clear history for me, with confirmation.
Future<void> confirmClearHistory(BuildContext context, String chatId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Clear history?'),
      content: const Text('Hides previous messages from your view only.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Clear')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await AppScope.of(context).chats.clearHistory(chatId);
    if (context.mounted) showToast(context, 'History cleared');
  } catch (_) {
    if (context.mounted) showToast(context, 'Could not clear', error: true);
  }
}
