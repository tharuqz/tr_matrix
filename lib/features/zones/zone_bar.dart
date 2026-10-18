import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/fancy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import 'zone_page.dart';
import 'zone_session.dart';

/// Floating bar shown while you are in a Zone but browsing other screens.
/// Shows a live timer plus mute, deafen, open and leave controls.
class ZoneBarOverlay extends StatelessWidget {
  final Widget child;
  const ZoneBarOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<ActiveZone?>(
          valueListenable: ZoneSession.active,
          builder: (_, a, __) => ValueListenableBuilder<bool>(
            valueListenable: ZoneSession.pageOpen,
            builder: (_, open, __) {
              final show = a != null && !open;
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: show ? MediaQuery.paddingOf(context).top + 8 : -120,
                child: IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: show ? 1 : 0,
                    child: a == null
                        ? const SizedBox.shrink()
                        : Center(child: _ZoneBar(zone: a)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ZoneBar extends StatefulWidget {
  final ActiveZone zone;
  const _ZoneBar({required this.zone});
  @override
  State<_ZoneBar> createState() => _ZoneBarState();
}

class _ZoneBarState extends State<_ZoneBar>
    with SingleTickerProviderStateMixin {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _tick.cancel();
    _glow.dispose();
    super.dispose();
  }

  void _open() {
    final nav = ZoneSession.navigatorKey.currentState?.overlay?.context;
    if (nav != null) openZone(nav, widget.zone.chatId, widget.zone.title);
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.zone.controller;
    final started = widget.zone.joinedAt ?? DateTime.now();
    return Material(
      color: Colors.transparent,
      child: ListenableBuilder(
        listenable: Listenable.merge([z, _glow]),
        builder: (context, _) {
          final c = context.tr;
          final accent = context.accent;
          return Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            decoration: BoxDecoration(
              color: c.surface1.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(TRRadius.pill),
              border: Border.all(color: accent.withValues(alpha: .45)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .18 + .22 * _glow.value),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: .25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _open,
                  borderRadius: BorderRadius.circular(TRRadius.pill),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c.success,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: c.success.withValues(
                                  alpha: .4 + .5 * _glow.value,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            '${plainName(widget.zone.title)} · Zone',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TRText.body(13, c.text1, w: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(TRRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                formatZoneElapsed(
                                  DateTime.now().difference(started),
                                ),
                                style: TRText.mono(12, accent).copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.people_alt_outlined,
                          size: 14,
                          color: c.text3,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${z.participants.length}',
                          style: TRText.body(12, c.text2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _btn(
                  context,
                  z.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  z.muted ? 'Unmute' : 'Mute',
                  z.toggleMute,
                  on: z.muted,
                ),
                _btn(
                  context,
                  z.deafened
                      ? Icons.headset_off_rounded
                      : Icons.headphones_rounded,
                  z.deafened ? 'Undeafen' : 'Deafen',
                  z.toggleDeafen,
                  on: z.deafened,
                ),
                _btn(context, Icons.open_in_full_rounded, 'Open Zone', _open),
                _btn(
                  context,
                  Icons.call_end_rounded,
                  'Leave Zone',
                  ZoneSession.leave,
                  danger: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _btn(
    BuildContext context,
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool on = false,
    bool danger = false,
  }) {
    final c = context.tr;
    final bg =
        danger ? c.danger : (on ? c.danger.withValues(alpha: .16) : c.surface2);
    final fg = danger ? Colors.white : (on ? c.danger : c.text1);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: fg),
          ),
        ),
      ),
    );
  }
}
