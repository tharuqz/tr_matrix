import 'package:flutter/material.dart';
import 'animated_emoji.dart';

/// Styled names/bios — same invisible-marker format as the website (src/lib/chat/fancy.ts).
const motionFx = [
  'rainbow',
  'shimmer',
  'neon',
  'wave',
  'pulse',
  'fire',
  'gradientShift',
  'aurora',
];
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

// ---- fonts — 1:1 with src/lib/chat/fancy.ts FANCY_FONTS ----
const fancyFonts = [
  'normal',
  'bold',
  'italic',
  'boldItalic',
  'script',
  'gothic',
  'outline',
  'sans',
  'mono',
  'bubble',
  'smallCaps',
  'wide',
  'retro',
  'elegant',
  'cyber',
];
const fontLabels = {
  'normal': 'Normal',
  'bold': 'Bold',
  'italic': 'Italic',
  'boldItalic': 'Bold italic',
  'script': 'Script',
  'gothic': 'Gothic',
  'outline': 'Outline',
  'sans': 'Sans bold',
  'mono': 'Typewriter',
  'bubble': 'Bubble',
  'smallCaps': 'Small caps',
  'wide': 'Wide',
  'retro': 'Retro',
  'elegant': 'Elegant',
  'cyber': 'Cyber',
};

class TextStyleSpec {
  final String font;
  final String? fx;
  final Color? color;
  const TextStyleSpec({this.font = 'normal', this.fx, this.color});
  bool get isStyled => font != 'normal' || fx != null || color != null;
  TextStyleSpec copyWith({
    String? font,
    String? fx,
    Color? color,
    bool clearFx = false,
    bool clearColor = false,
  }) =>
      TextStyleSpec(
        font: font ?? this.font,
        fx: clearFx ? null : (fx ?? this.fx),
        color: clearColor ? null : (color ?? this.color),
      );
}

const plainStyle = TextStyleSpec();

const _mark = '\u2063\u2063',
    _tick = '\u200C',
    _end = '\u2063',
    _cMark = '\u2064',
    _b0 = '\u200B',
    _b1 = '\u200C';

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
  // Fonts are stored as Unicode glyphs; fx/color wrap them via invisible markers.
  var out = fx != null && motionFx.contains(fx)
      ? '$_mark${_tick * (motionFx.indexOf(fx) + 1)}$_end$text'
      : text;
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

/// Encode with optional font transform: applyFont then fx/color markers.
String encodeStyled(String text, TextStyleSpec s) {
  final base = s.font == 'normal' ? text : applyFont(text, s.font);
  return encodeFancy(base, s.fx, s.color);
}

// ---- Unicode font mapping — verbatim port of fancy.ts applyFont ----

const Map<String, List<int?>> _baseMap = {
  'bold': [0x1D400, 0x1D41A, 0x1D7CE],
  'italic': [0x1D434, 0x1D44E, null],
  'boldItalic': [0x1D468, 0x1D482, 0x1D7CE],
  'script': [0x1D4D0, 0x1D4EA, 0x1D7CE],
  'gothic': [0x1D56C, 0x1D586, 0x1D7CE],
  'outline': [0x1D538, 0x1D552, 0x1D7D8],
  'sans': [0x1D5D4, 0x1D5EE, 0x1D7EC],
  'mono': [0x1D670, 0x1D68A, 0x1D7F6],
  'wide': [0xFF21, 0xFF41, 0xFF10],
  'retro': [0x1D400, 0x1D41A, 0x1D7CE],
  'elegant': [0x1D4D0, 0x1D4EA, null],
  'cyber': [0x1D5D4, 0x1D5EE, 0x1D7EC],
};
const _italicHoles = {'h': 0x210E};
const _outlineHoles = {
  'C': 0x2102,
  'H': 0x210D,
  'N': 0x2115,
  'P': 0x2119,
  'Q': 0x211A,
  'R': 0x211D,
  'Z': 0x2124,
};
const _smallCaps = 'ᴀʙᴄᴅᴇꜰɢʜɪᴊᴋʟᴍɴᴏᴘǫʀsᴛᴜᴠᴡxʏᴢ';

String applyFont(String input, String font) {
  if (font == 'normal' || input.isEmpty) return input;
  final out = StringBuffer();
  for (final r in input.runes) {
    final ch = String.fromCharCode(r);
    final upper = r >= 0x41 && r <= 0x5A,
        lower = r >= 0x61 && r <= 0x7A,
        digit = r >= 0x30 && r <= 0x39;
    if (font == 'smallCaps') {
      out.write(lower ? _smallCaps[r - 0x61] : ch);
      continue;
    }
    if (font == 'bubble') {
      if (upper) {
        out.write(String.fromCharCode(0x24B6 + r - 0x41));
        continue;
      }
      if (lower) {
        out.write(String.fromCharCode(0x24D0 + r - 0x61));
        continue;
      }
      if (digit) {
        out.write(String.fromCharCode(r == 0x30 ? 0x24EA : 0x2460 + r - 0x31));
        continue;
      }
      out.write(ch);
      continue;
    }
    if (font == 'wide' && r == 0x20) {
      out.write('\u3000');
      continue;
    }
    final base = _baseMap[font];
    if (base == null) {
      out.write(ch);
      continue;
    }
    final a = base[0]!, l = base[1]!, d = base[2];
    if (font == 'italic' && _italicHoles.containsKey(ch)) {
      out.write(String.fromCharCode(_italicHoles[ch]!));
    } else if (font == 'outline' && _outlineHoles.containsKey(ch)) {
      out.write(String.fromCharCode(_outlineHoles[ch]!));
    } else if (upper) {
      out.write(String.fromCharCode(a + r - 0x41));
    } else if (lower) {
      out.write(String.fromCharCode(l + r - 0x61));
    } else if (digit && d != null) {
      out.write(String.fromCharCode(d + r - 0x30));
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

/// Recover the plain source for an already-styled string (for editing).
MapEntry<String, String> readFancyFont(String input) {
  if (input.isEmpty) return const MapEntry('normal', '');
  // Build reverse maps lazily once.
  const source =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ';
  String bestFont = 'normal';
  int bestScore = 0;
  String bestPlain = input;
  for (final font in fancyFonts) {
    if (font == 'normal') continue;
    final rev = <String, String>{};
    for (final ch in source.split('')) {
      final s = applyFont(ch, font);
      if (s != ch) rev[s] = ch;
    }
    final chars = input.split('');
    final score = chars.where((c) => rev.containsKey(c)).length;
    final plain = chars.map((c) => rev[c] ?? c).join();
    if (applyFont(plain, font) != input) continue;
    if (score > bestScore) {
      bestScore = score;
      bestFont = font;
      bestPlain = plain;
    }
  }
  if (bestScore == 0) return MapEntry('normal', input);
  return MapEntry(bestFont, bestPlain);
}

/// Convenience: decode fx/color then recover font as well.
({String text, String font, String? fx, Color? color}) decodeStyled(
  String raw,
) {
  final f = decodeFancy(raw);
  final ff = readFancyFont(f.text);
  return (text: ff.value, font: ff.key, fx: f.fx, color: f.color);
}

/// Plain text without any markers (for previews, search, notifications).
String plainName(String raw) => decodeFancy(raw).text;

// Verbatim-ish web motion palette & per-fx easing/timing. Web uses
// a masked gradient that sweeps; flutter replicates via GradientRotation
// with per-fx durations that honor reduceMotion.
Duration _fxDuration(String fx, bool reduce) {
  if (reduce) return Duration.zero;
  return switch (fx) {
    'rainbow' => const Duration(milliseconds: 2200),
    'fire' => const Duration(milliseconds: 1400),
    'shimmer' => const Duration(milliseconds: 1600),
    'neon' => const Duration(milliseconds: 1800),
    'wave' => const Duration(milliseconds: 2400),
    'pulse' => const Duration(milliseconds: 1800),
    _ => const Duration(milliseconds: 2600),
  };
}

List<Color> _fxColors(String fx, Brightness brightness) {
  final light = brightness == Brightness.light;
  return switch (fx) {
    'rainbow' => const [
        Color(0xFFEF4444),
        Color(0xFFF59E0B),
        Color(0xFF22C55E),
        Color(0xFF3B82F6),
        Color(0xFFA855F7),
      ],
    'fire' => const [Color(0xFFF97316), Color(0xFFEF4444), Color(0xFFFACC15)],
    'neon' => light
        ? const [Color(0xFF0891B2), Color(0xFFC026D3)]
        : const [Color(0xFF22D3EE), Color(0xFFE879F9)],
    'aurora' => light
        ? const [Color(0xFF059669), Color(0xFF0891B2), Color(0xFF7C3AED)]
        : const [Color(0xFF34D399), Color(0xFF22D3EE), Color(0xFF8B5CF6)],
    'gradientShift' => light
        ? const [Color(0xFF7C3AED), Color(0xFFDB2777)]
        : const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    'shimmer' => light
        ? const [Color(0xFF52525B), Color(0xFFA1A1AA), Color(0xFF52525B)]
        : const [Color(0xFFE5E7EB), Color(0xFF9CA3AF), Color(0xFFE5E7EB)],
    'wave' => light
        ? const [Color(0xFF2563EB), Color(0xFF06B6D4)]
        : const [Color(0xFF60A5FA), Color(0xFF22D3EE)],
    'pulse' => light
        ? const [Color(0xFF111827), Color(0xFF6B7280)]
        : const [Color(0xFFF9FAFB), Color(0xFF9CA3AF)],
    _ => const [Color(0xFFE5E7EB), Color(0xFF9CA3AF), Color(0xFFE5E7EB)],
  };
}

/// Renders a styled name: colour and an animated gradient for motion effects.
class FancyText extends StatefulWidget {
  final String raw;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  const FancyText(
    this.raw, {
    super.key,
    required this.style,
    this.maxLines,
    this.textAlign,
  });
  @override
  State<FancyText> createState() => _FancyTextState();
}

class _FancyTextState extends State<FancyText>
    with SingleTickerProviderStateMixin {
  AnimationController? _ac;

  @override
  Widget build(BuildContext context) {
    final f = decodeFancy(widget.raw);
    final style =
        f.color != null ? widget.style.copyWith(color: f.color) : widget.style;
    final text = Text(
      f.text,
      style: style,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
    );
    if (f.fx == null) {
      return AnimatedEmojiText.hasAnimated(f.text)
          ? AnimatedEmojiText(f.text,
              style: style,
              maxLines: widget.maxLines,
              textAlign: widget.textAlign)
          : text;
    }
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _ac ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (reduce) {
      _ac!.stop();
    } else if (!_ac!.isAnimating) {
      _ac!.repeat();
    }
    final b = Theme.of(context).brightness;
    final colors = _fxColors(f.fx!, b);
    _ac!.duration = _fxDuration(f.fx!, reduce);
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
