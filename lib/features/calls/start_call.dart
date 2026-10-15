import 'package:flutter/material.dart';
import '../../core/app_scope.dart';
import '../../data/chat_actions.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'call_controller.dart';

/// Starts a voice/video call for any chat — 1:1 or group.
Future<void> startCallForChat(BuildContext context, String chatId, ChatItem? item, String kind) async {
  final scope = AppScope.of(context);
  final me = scope.auth.user?.id;
  if (me == null) return;
  try {
    var isGroup = item?.isGroup;
    String? other = item?.otherUserId;
    if (isGroup == null || (!isGroup && other == null)) {
      final row = await scope.chats.chatRow(chatId);
      isGroup = row?['is_group'] == true;
      if (!isGroup) other = (row?['user_a'] == me) ? (row?['user_b'] as String?) : (row?['user_a'] as String?);
    }
    if (isGroup) {
      final members = await scope.chats.groupMembers(chatId);
      await scope.calls.startGroupCall(
        chatId: chatId,
        title: item?.title ?? 'Group',
        kind: kind,
        members: [for (final m in members) GroupInvitee(m.profile.id, m.profile.displayName, m.profile.avatarUrl)],
      );
    } else if (other != null) {
      await scope.calls.startCall(
        chatId: chatId,
        peerUserId: other,
        peerName: item?.title ?? 'Contact',
        peerAvatar: item?.avatarUrl,
        kind: kind,
      );
    } else if (context.mounted) {
      showToast(context, 'Could not find who to call', error: true);
    }
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not start call: $e', error: true);
  }
}
