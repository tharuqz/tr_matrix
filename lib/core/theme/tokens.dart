import 'package:flutter/material.dart';

/// 1:1 port of src/design/tokens.json ("Obsidian Matrix").
class TRColors {
  final Color bg, surface1, surface2, surface3, border, text1, text2, text3;
  final Color success, warn, danger, bubbleIn, overlay;
  const TRColors({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.success,
    required this.warn,
    required this.danger,
    required this.bubbleIn,
    required this.overlay,
  });

  static const dark = TRColors(
    bg: Color(0xFF0B0D17),
    surface1: Color(0xFF12141F),
    surface2: Color(0xFF181B27),
    surface3: Color(0xFF1F2230),
    border: Color(0x1AFFFFFF),
    text1: Color(0xFFF5F6F8),
    text2: Color(0xFFA3A7B3),
    text3: Color(0xFF6B7080),
    success: Color(0xFF10B981),
    warn: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    bubbleIn: Color(0xFF1C1F2B),
    overlay: Color(0xA6000000),
  );

  static const amoled = TRColors(
    bg: Color(0xFF000000),
    surface1: Color(0xFF0A0A0C),
    surface2: Color(0xFF111114),
    surface3: Color(0xFF18181C),
    border: Color(0x17FFFFFF),
    text1: Color(0xFFF5F6F8),
    text2: Color(0xFFA3A7B3),
    text3: Color(0xFF6B7080),
    success: Color(0xFF10B981),
    warn: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    bubbleIn: Color(0xFF141418),
    overlay: Color(0xB3000000),
  );

  static const light = TRColors(
    bg: Color(0xFFFBFBFD),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFF2F3F6),
    surface3: Color(0xFFE9EBF0),
    border: Color(0x1F000000),
    text1: Color(0xFF16181F),
    text2: Color(0xFF555A66),
    text3: Color(0xFF8A8F9C),
    success: Color(0xFF059669),
    warn: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    bubbleIn: Color(0xFFEEF0F4),
    overlay: Color(0x4D000000),
  );
}

class TRAccent {
  static const defaultAccent = Color(0xFF22D3EE);
  static const swatches = [
    Color(0xFF22D3EE),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
  ];
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const receiptDelivered = Color(0xFF22D3EE);
  static const receiptSeen = Color(0xFF10B981);

  /// Text colour on top of accent (tokens: luminance > 0.4 ? dark : white).
  static Color on(Color accent) =>
      accent.computeLuminance() > 0.4 ? const Color(0xFF0B0D17) : Colors.white;
}

/// Tailwind-equivalent spacing / radii.
class TRSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0;
  static const s8 = 32.0, s10 = 40.0, s12 = 48.0, s16 = 64.0;
}

class TRRadius {
  static const sm = 8.0,
      md = 10.0,
      lg = 12.0,
      xl = 16.0,
      x2l = 20.0,
      x3l = 24.0;
  static const glass = 28.0, pill = 999.0;
}

class TRShadow {
  static List<BoxShadow> md(Color base) => [
    BoxShadow(
      color: base.withValues(alpha: .25),
      blurRadius: 6,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: base.withValues(alpha: .15),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];
  static List<BoxShadow> glow(Color accent) => [
    BoxShadow(
      color: accent.withValues(alpha: .35),
      blurRadius: 24,
      spreadRadius: -4,
    ),
  ];
}
