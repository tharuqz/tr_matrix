import '../../core/desktop_menu.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'chat_manage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/chat_extras.dart';
import '../../core/app_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/last_seen_text.dart';
import '../../core/security/app_lock.dart';
import 'chat_list_pane.dart' show lockChat;
import '../calls/start_call.dart';
import 'chat_search_sheet.dart';
import 'groups.dart';
import 'chat_theme_sheet.dart';

class ChatDetailsSheet extends StatelessWidget {
  final ChatItem item;
  const ChatDetailsSheet({super.key, required this.item});
  static Future<void> show(BuildContext c, ChatItem i) =>
      showAnchoredSheet<void>(
        large: true,
        context: c,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: .88,
          maxChildSize: .96,
          minChildSize: .5,
          expand: false,
          builder: (_, sc) => _Sheet(item: i, scroll: sc),
        ),
      );
  @override
  Widget build(BuildContext c) => const SizedBox.shrink();
}

class _Sheet extends StatelessWidget {
  final ChatItem item;
  final ScrollController scroll;
  const _Sheet({required this.item, required this.scroll});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final isGroup = item.isGroup;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(TRRadius.glass),
        ),
      ),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TRIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  isGroup ? 'Hive info' : 'Contact info',
                  textAlign: TextAlign.center,
                  style: TRText.body(16, c.text1, w: FontWeight.w700),
                ),
              ),
              TRIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 2),
              ),
              child: TRAvatar(name: item.title, url: item.avatarUrl, size: 112),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: TRText.display(20, c.text1),
          ),
          Center(
            child: isGroup
                ? Text('Hive', style: TRText.body(12, c.text3))
                : LastSeenText(userId: item.otherUserId, center: true),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Quick(
                icon: Icons.call_rounded,
                label: 'Voice',
                onTap: () => startCallForChat(context, item.id, item, 'voice'),
              ),
              const SizedBox(width: 10),
              _Quick(
                icon: Icons.videocam_rounded,
                label: 'Video',
                onTap: () => startCallForChat(context, item.id, item, 'video'),
              ),
              const SizedBox(width: 10),
              _Quick(
                icon: Icons.search_rounded,
                label: 'Search',
                onTap: () => ChatSearchSheet.show(context, item.id, (_) {}),
              ),
              const SizedBox(width: 10),
              _Quick(
                icon: item.muted
                    ? Icons.notifications_rounded
                    : Icons.notifications_off_outlined,
                label: item.muted ? 'Unmute' : 'Mute',
                onTap: () async {
                  await AppScope.of(context).chats.toggleMute(item.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: 'Chat theme',
            subtitle: 'Wallpaper, bubbles, composer, pattern, focus',
            onTap: () => ChatThemeSheet.show(context, item.id),
          ),
          const SizedBox(height: 10),
          _Section(
            title: 'Disappearing messages',
            subtitle: 'Off / 1h / 24h / 7d / 90d',
            onTap: () => _pickDisappearing(context),
          ),
          const SizedBox(height: 10),
          _Section(
            title: AppLock.instance.isChatLocked(item.id)
                ? 'Unlock chat'
                : 'Lock & hide chat',
            subtitle: AppLock.instance.isChatLocked(item.id)
                ? 'Show it in your chat list again'
                : 'Hide it from the list; open with PIN or fingerprint',
            onTap: () async {
              if (AppLock.instance.isChatLocked(item.id)) {
                await AppLock.instance.setChatLocked(item.id, false);
                if (context.mounted) showToast(context, 'Chat unlocked');
              } else {
                await lockChat(context, item.id);
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 10),
          _Section(
            title: 'Shared media & links',
            subtitle: 'Photos, files and links',
            onTap: () => showToast(context, 'Media gallery coming soon'),
          ),
          const SizedBox(height: 18),
          Text(
            'Danger zone',
            style: TRText.body(12, c.danger, w: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _Danger(
            label: 'Clear history',
            icon: Icons.cleaning_services_outlined,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Clear history?'),
                  content: const Text('Messages will be cleared for you only.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                try {
                  await AppScope.of(context).chats.clearHistory(item.id);
                  if (context.mounted) {
                    showToast(context, 'History cleared');
                    Navigator.pop(context);
                  }
                } catch (_) {
                  if (context.mounted)
                    showToast(context, 'Could not clear', error: true);
                }
              }
            },
          ),
          _Danger(
            label: 'Block user',
            icon: Icons.block_rounded,
            danger: true,
            onTap: () => toggleBlock(context, item),
          ),
          _Danger(
            label: 'Delete chat',
            icon: Icons.delete_outline_rounded,
            danger: true,
            onTap: () async {
              if (await confirmDeleteChat(context, item) && context.mounted) {
                Navigator.pop(context);
                GoRouter.of(context).go('/app');
              }
            },
          ),
          if (isGroup) ...[
            const SizedBox(height: 10),
            _Section(
              title: 'Hive members',
              subtitle: 'Add, remove or leave',
              onTap: () => showGroupInfo(context, item.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Quick({required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TRRadius.xl),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(TRRadius.xl),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: c.text1),
              const SizedBox(height: 4),
              Text(label, style: TRText.body(11, c.text2, w: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title, subtitle;
  final VoidCallback? onTap;
  const _Section({required this.title, required this.subtitle, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TRRadius.x2l),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(TRRadius.x2l),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TRText.body(14, c.text1, w: FontWeight.w600),
                  ),
                  Text(subtitle, style: TRText.body(12, c.text3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.text3),
          ],
        ),
      ),
    );
  }
}

class _Danger extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool danger;
  final VoidCallback onTap;
  const _Danger({
    required this.label,
    required this.icon,
    this.danger = false,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TRRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: danger ? c.danger.withValues(alpha: .08) : c.surface2,
            borderRadius: BorderRadius.circular(TRRadius.lg),
            border: Border.all(
              color: danger ? c.danger.withValues(alpha: .3) : c.border,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: danger ? c.danger : c.text1),
              const SizedBox(width: 10),
              Text(
                label,
                style: TRText.body(
                  14,
                  danger ? c.danger : c.text1,
                  w: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _pickDisappearing(BuildContext context) async {
  final c = context.tr;
  const opts = [
    (null, 'Off'),
    (3600, '1 hour'),
    (86400, '24 hours'),
    (604800, '7 days'),
    (7776000, '90 days'),
  ];
  await showAnchoredSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(TRRadius.glass)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Disappearing messages',
                style: TRText.display(16, c.text1),
              ),
            ),
            for (final o in opts)
              ListTile(
                title: Text(o.$2),
                onTap: () {
                  Navigator.pop(ctx);
                  showToast(context, 'Disappearing: ${o.$2}');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
