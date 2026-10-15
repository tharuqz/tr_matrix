import 'package:flutter/material.dart';

/// Styled names/bios — same invisible-marker format as the website (src/lib/chat/fancy.ts).
const motionFx = ['rainbow', 'shimmer', 'neon', 'wave', 'pulse', 'fire', 'gradientShift', 'aurora'];
const motionLabels = {
  'rainbow': 'Rainbow',
  'shimmer': 'Shimmer',
  'neon': 'Neon',
  'wave': 'Wave',
  'pulse': 'Pulse',
  'fire': 'Fire',
  'gradientShift': 'Gradient',
  'aurora': 'Aurora',
};

const _mark = '\u2063\u2063', _tick = '\u200C', _end = '\u2063', _cMark = '\u2064', _b0 = '\u200B', _b1 = '\u200C';

class Fancy {
  final String text;
  final String? fx;
  final Color? color;
  const Fancy(this.text, this.fx, this.color);
}

Fancy decodeFancy(String raw) {
  if (raw.isEmpty) return Fancy(raw, null, null);
  var rest = raw;
  Color? color;
  if (raw.startsWith(_cMark) && raw.length >= 26 && raw[25] == _cMark) {
    var rgb = 0;
    var ok = true;
    for (var i = 1; i <= 24; i++) {
      final ch = raw[i];
      if (ch != _b0 && ch != _b1) {
        ok = false;
        break;
      }
      rgb = (rgb << 1) | (ch == _b1 ? 1 : 0);
    }
    if (ok) {
      color = Color(0xFF000000 | rgb);
      rest = raw.substring(26);
    }
  }
  if (!rest.startsWith(_mark)) return Fancy(rest, null, color);
  var i = _mark.length, n = 0;
  while (i < rest.length && rest[i] == _tick) {
    n++;
    i++;
  }
  if (i < rest.length && rest[i] == _end && n >= 1 && n <= motionFx.length) {
    return Fancy(rest.substring(i + 1), motionFx[n - 1], color);
  }
  return Fancy(rest, null, color);
}

String encodeFancy(String text, String? fx, Color? color) {
  if (text.isEmpty) return text;
  var out = fx != null && motionFx.contains(fx) ? '$_mark${_tick * (motionFx.indexOf(fx) + 1)}$_end$text' : text;
  if (color != null) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    final bits = StringBuffer();
    for (var b = 23; b >= 0; b--) {
      bits.write((rgb >> b) & 1 == 1 ? _b1 : _b0);
    }
    out = '$_cMark$bits$_cMark$out';
  }
  return out;
}

/// Plain text without any markers (for previews, search, notifications).
String plainName(String raw) => decodeFancy(raw).text;

List<Color> _fxColors(String fx) => switch (fx) {
      'rainbow' => const [Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFF22C55E), Color(0xFF3B82F6), Color(0xFFA855F7)],
      'fire' => const [Color(0xFFF97316), Color(0xFFEF4444), Color(0xFFFACC15)],
      'neon' => const [Color(0xFF22D3EE), Color(0xFFE879F9)],
      'aurora' => const [Color(0xFF34D399), Color(0xFF22D3EE), Color(0xFF8B5CF6)],
      'gradientShift' => const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
      _ => const [Color(0xFFE5E7EB), Color(0xFF9CA3AF), Color(0xFFE5E7EB)],
    };

/// Renders a styled name: colour and an animated gradient for motion effects.
class FancyText extends StatefulWidget {
  final String raw;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  const FancyText(this.raw, {super.key, required this.style, this.maxLines, this.textAlign});
  @override
  State<FancyText> createState() => _FancyTextState();
}

class _FancyTextState extends State<FancyText> with SingleTickerProviderStateMixin {
  AnimationController? _ac;

  @override
  Widget build(BuildContext context) {
    final f = decodeFancy(widget.raw);
    final style = f.color != null ? widget.style.copyWith(color: f.color) : widget.style;
    final text = Text(f.text, style: style, maxLines: widget.maxLines, overflow: TextOverflow.ellipsis, textAlign: widget.textAlign);
    if (f.fx == null) return text;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _ac ??= AnimationController(vsync: this, duration: const Duration(seconds: 3));
    if (reduce) {
      _ac!.stop();
    } else if (!_ac!.isAnimating) {
      _ac!.repeat();
    }
    final colors = _fxColors(f.fx!);
    return AnimatedBuilder(
      animation: _ac!,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: [...colors, colors.first],
          transform: GradientRotation(_ac!.value * 6.283),
        ).createShader(r),
        child: child,
      ),
      child: text,
    );
  }

  @override
  void dispose() {
    _ac?.dispose();
    super.dispose();
  }
}
