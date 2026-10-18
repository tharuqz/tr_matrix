import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_scope.dart';
import '../../core/fancy.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_extras.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/last_seen_text.dart';
import '../calls/start_call.dart';
import 'chat_list_pane.dart' show lockChat;
import 'chat_search_sheet.dart';
import 'chat_manage.dart';
import 'package:go_router/go_router.dart';
import 'chat_theme_sheet.dart';
import 'disappearing_menu.dart';
import 'groups.dart';

/// Profile / info panel for a chat. Right side on desktop, bottom sheet on
/// mobile. Contains profile header, quick actions, appearance (themes) and
/// chat controls (mute, pin, archive, disappearing, lock, clear).
class ChatInfoPanel extends StatefulWidget {
  final ChatItem? item;
  final ScrollController? scrollController;
  const ChatInfoPanel({super.key, this.item, this.scrollController});
  @override
  State<ChatInfoPanel> createState() => _ChatInfoPanelState();
}

class _ChatInfoPanelState extends State<ChatInfoPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  String? _bio, _username;
  bool? _muted, _pinned, _archived;

  ChatItem? get item => widget.item;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant ChatInfoPanel old) {
    super.didUpdateWidget(old);
    if (old.item?.id != widget.item?.id) {
      _bio = _username = null;
      _muted = _pinned = _archived = null;
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = item?.otherUserId;
    if (uid == null || item?.isGroup == true) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('username, bio')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _bio = row['bio'] as String?;
        _username = row['username'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _toggle(String what) async {
    final it = item;
    if (it == null) return;
    final repo = AppScope.of(context).chats;
    try {
      switch (what) {
        case 'mute':
          await repo.toggleMute(it.id);
          setState(() => _muted = !(_muted ?? it.muted));
          break;
        case 'pin':
          await repo.togglePin(it.id);
          setState(() => _pinned = !(_pinned ?? it.pinned));
          break;
        case 'archive':
          await repo.toggleArchive(it.id);
          setState(() => _archived = !(_archived ?? it.archived));
          break;
      }
      repo.refreshChats().catchError((_) {});
    } catch (_) {
      if (mounted)
        showToast(context, 'Could not update this chat', error: true);
    }
  }

  Future<void> _clear() async {
    final it = item;
    if (it == null) return;
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
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).chats.clearHistory(it.id);
      if (mounted) showToast(context, 'History cleared');
    } catch (_) {
      if (mounted) showToast(context, 'Could not clear', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final acc = context.accent;
    final it = item;
    final title = it?.title ?? 'Chat';
    final isGroup = it?.isGroup == true;
    final locked = it != null && AppLock.instance.isChatLocked(it.id);
    final sheet = widget.scrollController != null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface1.withValues(alpha: .92),
        borderRadius: sheet
            ? const BorderRadius.vertical(top: Radius.circular(TRRadius.glass))
            : null,
      ),
      clipBehavior: sheet ? Clip.antiAlias : Clip.none,
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.zero,
        children: [
          // ---------- Header: animated cover + glowing avatar ----------
          SizedBox(
            height: 300,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Cover banner with the moving gradient.
                Positioned(
                  left: 12,
                  right: 12,
                  top: sheet ? 22 : 12,
                  height: 128,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TRRadius.x2l),
                    child: AnimatedBuilder(
                      animation: _glow,
                      builder: (_, __) {
                        final t = _glow.value * 2 * math.pi;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(math.cos(t), math.sin(t)),
                              end: Alignment(-math.cos(t), -math.sin(t)),
                              colors: [
                                acc.withValues(alpha: .55),
                                c.surface2,
                                acc.withValues(alpha: .25),
                              ],
                            ),
                            border: Border.all(color: c.border),
                            borderRadius: BorderRadius.circular(TRRadius.x2l),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (sheet)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.text3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: sheet ? 92 : 82,
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _glow,
                        builder: (_, child) {
                          final p =
                              (math.sin(_glow.value * 2 * math.pi) + 1) / 2;
                          return Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                transform: GradientRotation(
                                  _glow.value * 2 * math.pi,
                                ),
                                colors: [acc, acc.withValues(alpha: .2), acc],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: acc.withValues(alpha: .25 + .3 * p),
                                  blurRadius: 18 + 14 * p,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.surface1,
                          ),
                          child: TRAvatar(
                            name: title,
                            url: it?.avatarUrl,
                            size: 96,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: FancyText(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TRText.display(21, c.text1),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Pill(
                            child: isGroup
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        Icon(Icons.hexagon_outlined,
                                            size: 13, color: acc),
                                        const SizedBox(width: 5),
                                        Text('Hive',
                                            style: TRText.body(12, c.text2,
                                                w: FontWeight.w600)),
                                      ])
                                : LastSeenText(
                                    userId: it?.otherUserId, center: true),
                          ),
                          if (!isGroup && _username != null)
                            _Pill(
                              child: Text('@$_username',
                                  style: TRText.mono(12, c.text2)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------- Quick actions ----------
                Row(
                  children: [
                    _Quick(
                      icon: Icons.call_rounded,
                      label: 'Voice',
                      onTap: it == null
                          ? null
                          : () => startCallForChat(context, it.id, it, 'voice'),
                    ),
                    const SizedBox(width: 8),
                    _Quick(
                      icon: Icons.videocam_rounded,
                      label: 'Video',
                      onTap: it == null
                          ? null
                          : () => startCallForChat(context, it.id, it, 'video'),
                    ),
                    const SizedBox(width: 8),
                    _Quick(
                      icon: Icons.search_rounded,
                      label: 'Search',
                      onTap: it == null
                          ? null
                          : () => ChatSearchSheet.show(context, it.id, (_) {}),
                    ),
                    const SizedBox(width: 8),
                    _Quick(
                      icon: (_muted ?? it?.muted ?? false)
                          ? Icons.notifications_rounded
                          : Icons.notifications_off_outlined,
                      label: (_muted ?? it?.muted ?? false) ? 'Unmute' : 'Mute',
                      onTap: it == null ? null : () => _toggle('mute'),
                    ),
                  ],
                ),

                // ---------- About ----------
                if (!isGroup && (_bio?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 16),
                  _Card(
                    children: [
                      if (_bio?.isNotEmpty ?? false)
                        _InfoRow(
                          icon: Icons.info_outline_rounded,
                          label: 'About',
                          child: FancyText(
                            _bio!,
                            style: TRText.body(14, c.text1),
                          ),
                        ),
                    ],
                  ),
                ],

                // ---------- Appearance ----------
                _Header('Appearance'),
                _Card(
                  children: [
                    _Tile(
                      icon: Icons.palette_outlined,
                      title: 'Chat theme & wallpaper',
                      subtitle: 'Wallpaper, background, bubbles, composer',
                      onTap: it == null
                          ? null
                          : () => ChatThemeSheet.show(context, it.id),
                    ),
                  ],
                ),

                // ---------- Chat controls ----------
                _Header('Chat controls'),
                _Card(
                  children: [
                    _SwitchTile(
                      icon: Icons.notifications_off_outlined,
                      title: 'Mute notifications',
                      value: _muted ?? it?.muted ?? false,
                      onChanged: it == null ? null : (_) => _toggle('mute'),
                    ),
                    _SwitchTile(
                      icon: Icons.push_pin_outlined,
                      title: 'Pin to top',
                      value: _pinned ?? it?.pinned ?? false,
                      onChanged: it == null ? null : (_) => _toggle('pin'),
                    ),
                    _SwitchTile(
                      icon: Icons.archive_outlined,
                      title: 'Archive chat',
                      value: _archived ?? it?.archived ?? false,
                      onChanged: it == null ? null : (_) => _toggle('archive'),
                    ),
                    if (it != null)
                      DisappearingMenu(chatId: it.id, labeled: true),
                    _Tile(
                      icon: locked
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                      title: locked ? 'Unlock chat' : 'Lock & hide chat',
                      subtitle: locked
                          ? 'Show it in your chat list again'
                          : 'Open with PIN or fingerprint',
                      onTap: it == null
                          ? null
                          : () async {
                              if (locked) {
                                await AppLock.instance.setChatLocked(
                                  it.id,
                                  false,
                                );
                                if (context.mounted)
                                  showToast(context, 'Chat unlocked');
                              } else {
                                await lockChat(context, it.id);
                              }
                              if (mounted) setState(() {});
                            },
                    ),
                    if (isGroup)
                      _Tile(
                        icon: Icons.groups_rounded,
                        title: 'Hive members',
                        subtitle: 'Add, remove or leave',
                        onTap: () => showGroupInfo(context, it!.id),
                      ),
                  ],
                ),

                // ---------- Danger ----------
                _Header('Danger zone', danger: true),
                _Card(
                  children: [
                    _Tile(
                      icon: Icons.cleaning_services_outlined,
                      title: 'Clear history',
                      subtitle: 'Only for you',
                      danger: true,
                      onTap: it == null ? null : _clear,
                    ),
                    if (it != null && !it.isGroup && it.otherUserId != null)
                      _Tile(
                        icon: Icons.block_rounded,
                        title: 'Block user',
                        subtitle: 'Stop messages and calls from them',
                        danger: true,
                        onTap: () => toggleBlock(context, it),
                      ),
                    _Tile(
                      icon: Icons.delete_outline_rounded,
                      title: 'Delete chat',
                      subtitle: 'For you, or for everyone',
                      danger: true,
                      onTap: it == null
                          ? null
                          : () async {
                              if (await confirmDeleteChat(context, it) &&
                                  context.mounted) {
                                GoRouter.of(context).go('/app');
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  final bool danger;
  const _Header(this.text, {this.danger = false});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Text(
        text.toUpperCase(),
        style: TRText.body(11, danger ? c.danger : c.text3, w: FontWeight.w700),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Divider(height: 1, color: c.border, indent: 52));
      items.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TRRadius.x2l),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: items),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBox(this.icon, this.color);
  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final bool danger;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final col = danger ? c.danger : context.accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            _IconBox(icon, col),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TRText.body(
                      14,
                      danger ? c.danger : c.text1,
                      w: FontWeight.w600,
                    ),
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

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            _IconBox(icon, context.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TRText.body(14, c.text1, w: FontWeight.w600),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: context.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBox(icon, context.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TRText.body(11, c.text3, w: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                child,
              ],
            ),
          ),
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
      child: Hoverable(
        tooltip: label,
        onTap: onTap ?? () {},
        builder: (_, h) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 76,
          decoration: BoxDecoration(
            color: h ? context.accent.withValues(alpha: .16) : c.surface2,
            borderRadius: BorderRadius.circular(TRRadius.xl),
            border: Border.all(
              color: h ? context.accent.withValues(alpha: .5) : c.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.accent.withValues(alpha: h ? .28 : .14),
                ),
                child: Icon(icon, size: 19, color: context.accent),
              ),
              const SizedBox(height: 5),
              Text(label, style: TRText.body(11, c.text2, w: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded label under the name (status, username).
class _Pill extends StatelessWidget {
  final Widget child;
  const _Pill({required this.child});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TRRadius.pill),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}
