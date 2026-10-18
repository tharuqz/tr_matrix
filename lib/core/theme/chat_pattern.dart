import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'chat_appearance.dart';

/// Draws the chat "Pattern" effect (flow / contour / arcade) so the chat
/// screen and the theme preview show exactly the same thing.
class ChatPatternLayer extends StatefulWidget {
  final ChatAppearance ap;
  final Color accent;
  const ChatPatternLayer({super.key, required this.ap, required this.accent});
  @override
  State<ChatPatternLayer> createState() => _ChatPatternLayerState();
}

class _ChatPatternLayerState extends State<ChatPatternLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
      vsync: this, duration: const Duration(seconds: 18));

  bool get _animate =>
      widget.ap.effectMotion && widget.ap.effect != 'none';

  @override
  void initState() {
    super.initState();
    if (_animate) _t.repeat();
  }

  @override
  void didUpdateWidget(covariant ChatPatternLayer old) {
    super.didUpdateWidget(old);
    final reduce = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.disableAnimations;
    if (_animate && !reduce) {
      if (!_t.isAnimating) _t.repeat();
    } else {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Color get _color {
    final s = widget.ap.effectColor;
    if (s == 'auto' || !s.startsWith('#')) return widget.accent;
    try {
      return Color(int.parse('FF${s.substring(1)}', radix: 16));
    } catch (_) {
      return widget.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ap = widget.ap;
    if (ap.effect == 'none' || ap.effectVisibility <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _PatternPainter(
              kind: ap.effect,
              color: _color.withValues(alpha: ap.effectVisibility / 100),
              scale: ap.effectScale / 100,
              t: _t,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final String kind;
  final Color color;
  final double scale;
  final Animation<double> t;
  _PatternPainter(
      {required this.kind,
      required this.color,
      required this.scale,
      required this.t})
      : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final phase = t.value * 2 * math.pi;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;
    switch (kind) {
      case 'flow':
        final gap = 34.0 * scale;
        final amp = 12.0 * scale;
        for (double y = -gap; y < size.height + gap; y += gap) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x <= size.width; x += 8) {
            path.lineTo(
                x, y + math.sin(x / (60 * scale) + phase + y / 90) * amp);
          }
          canvas.drawPath(path, p);
        }
      case 'contour':
        final gap = 26.0 * scale;
        final centers = [
          Offset(size.width * .2, size.height * .25),
          Offset(size.width * .85, size.height * .7),
        ];
        final maxR = size.longestSide;
        for (final c in centers) {
          for (double r = gap; r < maxR; r += gap) {
            final path = Path();
            for (int i = 0; i <= 72; i++) {
              final a = i / 72 * 2 * math.pi;
              final wob = 1 + .06 * math.sin(a * 3 + phase + r / 40);
              final pt = c + Offset(math.cos(a), math.sin(a)) * r * wob;
              i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
            }
            canvas.drawPath(path, p);
          }
        }
      case 'arcade':
        final gap = 22.0 * scale;
        final fill = Paint()..color = color;
        final shift = t.value * gap;
        for (double y = 0; y < size.height + gap; y += gap) {
          for (double x = 0; x < size.width + gap; x += gap) {
            final on = ((x / gap).floor() + (y / gap).floor()) % 3 == 0;
            final s = (on ? 3.2 : 1.6) * scale;
            canvas.drawRect(
                Rect.fromCenter(
                    center: Offset(x, (y + shift) % (size.height + gap)),
                    width: s,
                    height: s),
                fill);
          }
        }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter o) =>
      o.kind != kind || o.color != color || o.scale != scale;
}
