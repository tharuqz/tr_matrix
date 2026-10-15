import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'groups.dart';
import '../calls/start_call.dart';
import 'wallpaper.dart';

/// Right-side info panel (desktop) / bottom sheet (mobile).
class ChatInfoPanel extends StatelessWidget {
  final ChatItem? item;
  final ScrollController? scrollController;
  const ChatInfoPanel({super.key, this.item, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final title = item?.title ?? 'Chat';
    return Container(
      decoration: BoxDecoration(
        color: c.surface1.withValues(alpha: .85),
        borderRadius: scrollController != null ? const BorderRadius.vertical(top: Radius.circular(TRRadius.glass)) : null,
      ),
      child: ListView(controller: scrollController, padding: const EdgeInsets.all(24), children: [
        if (scrollController != null)
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: c.text3, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        Center(child: TRAvatar(name: title, url: item?.avatarUrl, size: 96)),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: TRText.display(20, c.text1)),
        const SizedBox(height: 4),
        Text(item?.isGroup == true ? 'Group' : 'Direct message', textAlign: TextAlign.center, style: TRText.body(13, c.text2)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Action(icon: Icons.call_rounded, label: 'Call', onTap: item == null ? null : () => startCallForChat(context, item!.id, item, 'voice')),
          _Action(icon: Icons.videocam_rounded, label: 'Video', onTap: item == null ? null : () => startCallForChat(context, item!.id, item, 'video')),
          _Action(icon: Icons.search_rounded, label: 'Search'),
          _Action(icon: Icons.notifications_off_outlined, label: item?.muted == true ? 'Unmute' : 'Mute'),
        ]),
        const SizedBox(height: 24),
        if (item?.isGroup == true) ...[
          _Section(title: 'Group members', subtitle: 'Add, remove or leave', onTap: () => showGroupInfo(context, item!.id)),
          const SizedBox(height: 10),
        ],
        _Section(
          title: 'Chat wallpaper',
          subtitle: 'Presets or your own picture',
          onTap: item == null ? null : () => showWallpaperPicker(context, item!.id, (_) => showToast(context, 'Wallpaper updated — reopen the chat to see it')),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _Action({required this.icon, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Hoverable(
        tooltip: label,
        onTap: onTap ?? () {},
        builder: (_, h) => Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: h ? context.accent.withValues(alpha: .18) : c.surface2,
              borderRadius: BorderRadius.circular(TRRadius.xl),
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 20, color: h ? context.accent : c.text1),
          ),
          const SizedBox(height: 6),
          Text(label, style: TRText.body(11, c.text2, w: FontWeight.w600)),
        ]),
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
    return Hoverable(onTap: onTap, builder: (_, __) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(TRRadius.x2l), border: Border.all(color: c.border)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TRText.body(14, c.text1, w: FontWeight.w600)),
            Text(subtitle, style: TRText.body(12, c.text3)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.text3),
      ]),
    ));
  }
}
