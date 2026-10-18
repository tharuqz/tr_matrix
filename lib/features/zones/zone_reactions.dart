import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/animated_emoji.dart';
import 'zone_controller.dart';

const kZoneReactionEmojis = ['👍', '❤️', '😂', '🔥', '🎉', '👀', '🙌', '🤯'];

/// Animated reaction button with a press bounce.
class ZoneReactionButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;
  const ZoneReactionButton(this.emoji, {super.key, required this.onTap});

  @override
  State<ZoneReactionButton> createState() => _ZoneReactionButtonState();
}

class _ZoneReactionButtonState extends State<ZoneReactionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'React ${widget.emoji}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .82 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHighest.withValues(alpha: .55),
            ),
            child: AnimatedEmoji(widget.emoji, size: 30),
          ),
        ),
      ),
    );
  }
}

/// Glowing animated emoji that float up from the bottom of the zone.
class ZoneFloatingReactions extends StatelessWidget {
  final List<ZoneReaction> reactions;
  final String Function(String userId) nameOf;
  const ZoneFloatingReactions(
      {super.key, required this.reactions, required this.nameOf});

  @override
  Widget build(BuildContext context) {
    final list = reactions.length > 14
        ? reactions.sublist(reactions.length - 14)
        : reactions;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (_, box) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final r in list)
              _FloatingReaction(
                key: ValueKey(r.id),
                reaction: r,
                name: nameOf(r.from),
                area: box.biggest,
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingReaction extends StatefulWidget {
  final ZoneReaction reaction;
  final String name;
  final Size area;
  const _FloatingReaction(
      {super.key,
      required this.reaction,
      required this.name,
      required this.area});

  @override
  State<_FloatingReaction> createState() => _FloatingReactionState();
}

class _FloatingReactionState extends State<_FloatingReaction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..forward();
  late final int _seed = widget.reaction.id.hashCode;

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rnd = math.Random(_seed);
    final w = widget.area.width.isFinite ? widget.area.width : 400.0;
    final h = widget.area.height.isFinite ? widget.area.height : 400.0;
    final startX = w * (.55 + rnd.nextDouble() * .35);
    final drift = (rnd.nextDouble() - .5) * 90;
    final scale = .9 + rnd.nextDouble() * .4;
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_ac.value);
        final pop = _ac.value < .12
            ? Curves.easeOutBack.transform(_ac.value / .12) * 1.2
            : 1.2 - .4 * t;
        final opacity = _ac.value < .1
            ? _ac.value / .1
            : _ac.value > .8
                ? (1 - _ac.value) / .2
                : 1.0;
        final wobble = math.sin(_ac.value * math.pi * 6) * .14;
        return Positioned(
          left: startX + drift * t - 32,
          bottom: 8 + (h * .75) * t,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: wobble,
              child: Transform.scale(scale: pop * scale, child: child),
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: cs.primary.withValues(alpha: .55),
                    blurRadius: 22,
                    spreadRadius: 2),
              ],
            ),
            child: RepaintBoundary(
                child: AnimatedEmoji(widget.reaction.emoji, size: 56)),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(widget.name,
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
