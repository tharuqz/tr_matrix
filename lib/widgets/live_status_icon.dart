import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';

enum MsgStatus { sending, sent, delivered, seen }

/// Tiny animated status mark for your own messages (icon only, no text).
///  sending   → spinning arc
///  sent      → one soft breathing dot
///  delivered → two dots that slide together
///  seen      → glowing ring + core with a slow orbiting spark
class LiveStatusIcon extends StatefulWidget {
  final MsgStatus status;
  final Color muted;
  final double size;
  const LiveStatusIcon({
    super.key,
    required this.status,
    required this.muted,
    this.size = 14,
  });

  @override
  State<LiveStatusIcon> createState() => _LiveStatusIconState();
}

class _LiveStatusIconState extends State<LiveStatusIcon>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void didUpdateWidget(covariant LiveStatusIcon old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: widget.status.name,
      child: SizedBox(
        width: widget.size * 1.3,
        height: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_loop, _enter]),
            builder: (_, __) => CustomPaint(
              painter: _StatusPainter(
                status: widget.status,
                t: reduce ? 0.25 : _loop.value,
                enter: reduce ? 1 : Curves.easeOutBack.transform(_enter.value),
                muted: widget.muted,
                blue: TRAccent.receiptDelivered,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPainter extends CustomPainter {
  final MsgStatus status;
  final double t, enter;
  final Color muted, blue;
  _StatusPainter({
    required this.status,
    required this.t,
    required this.enter,
    required this.muted,
    required this.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final c = Offset(size.width / 2, h / 2);
    final r = h * .22;
    final fill = Paint()..isAntiAlias = true;
    final wave = (math.sin(t * math.pi * 2) + 1) / 2; // 0..1

    switch (status) {
      case MsgStatus.sending:
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * .12
          ..strokeCap = StrokeCap.round
          ..color = muted;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: h * .3),
          t * math.pi * 4,
          math.pi * 1.3,
          false,
          p,
        );
      case MsgStatus.sent:
        fill.color = muted.withValues(alpha: .65 + .35 * wave);
        canvas.drawCircle(c, r * (.9 + .12 * wave) * enter, fill);
      case MsgStatus.delivered:
        final gap = h * .34 * enter;
        fill.color = blue.withValues(alpha: .55);
        canvas.drawCircle(c.translate(-gap / 2, 0), r, fill);
        fill.color = blue;
        canvas.drawCircle(c.translate(gap / 2, 0), r * (1 + .08 * wave), fill);
      case MsgStatus.seen:
        final glow = Paint()
          ..color = blue.withValues(alpha: .25 + .25 * wave)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * .18);
        canvas.drawCircle(c, h * .36 * enter, glow);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * .1
          ..color = blue;
        canvas.drawCircle(c, h * .3 * enter, ring);
        fill.color = blue;
        canvas.drawCircle(c, h * .12 * enter, fill);
        // orbiting spark
        final a = t * math.pi * 2;
        fill.color = blue.withValues(alpha: .9);
        canvas.drawCircle(
          c + Offset(math.cos(a), math.sin(a)) * (h * .3 * enter),
          h * .07,
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _StatusPainter o) =>
      o.t != t || o.enter != enter || o.status != status || o.muted != muted;
}
