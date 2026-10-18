import '../../core/desktop_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_actions.dart';
import '../../data/models.dart';

enum MsgAction { reply, copy, edit, delete, forward, pin }

/// Long-press (phone) / right-click (computer) menu: quick reactions + actions.
Future<void> showMessageActions(
  BuildContext context, {
  required Message msg,
  required bool mine,
  required String? myReaction,
  bool isPinned = false,
  required void Function(String? emoji) onReact,
  required void Function(MsgAction) onAction,
}) {
  HapticFeedback.mediumImpact();
  final canEdit = mine &&
      !msg.deleted &&
      msg.mediaUrl == null &&
      (msg.content?.isNotEmpty ?? false);
  return showAnchoredSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) {
      final c = ctx.tr;
      Widget item(
        IconData i,
        String label,
        MsgAction a, {
        bool danger = false,
      }) =>
          ListTile(
            leading: Icon(i, color: danger ? c.danger : c.text1),
            title: Text(label,
                style: TRText.body(15, danger ? c.danger : c.text1)),
            onTap: () {
              Navigator.pop(ctx);
              onAction(a);
            },
          );
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(TRRadius.glass),
          border: Border.all(color: c.border),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!msg.deleted)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in quickReactions)
                          InkWell(
                            borderRadius: BorderRadius.circular(30),
                            onTap: () {
                              Navigator.pop(ctx);
                              onReact(myReaction == e ? null : e);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: myReaction == e
                                    ? ctx.accent.withValues(alpha: .25)
                                    : c.surface2,
                              ),
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!msg.deleted)
                  item(Icons.reply_rounded, 'Reply', MsgAction.reply),
                if (!msg.deleted)
                  item(Icons.forward_rounded, 'Forward', MsgAction.forward),
                if (!msg.deleted)
                  item(
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    isPinned ? 'Unpin' : 'Pin',
                    MsgAction.pin,
                  ),
                if (msg.content?.isNotEmpty ?? false)
                  item(Icons.copy_rounded, 'Copy text', MsgAction.copy),
                if (canEdit) item(Icons.edit_outlined, 'Edit', MsgAction.edit),
                if (mine && !msg.deleted)
                  item(
                    Icons.delete_outline_rounded,
                    'Delete for everyone',
                    MsgAction.delete,
                    danger: true,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
