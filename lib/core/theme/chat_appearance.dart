import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tokens.dart';

const chatThemes = [
  ('classic', 'Classic', Color(0xFF10B981)),
  ('ocean', 'Ocean', Color(0xFF3B82F6)),
  ('rose', 'Rose', Color(0xFFEC4899)),
  ('mono', 'Graphite', Color(0xFF6B7080)),
];

class ChatAppearance {
  final String effect;
  final String effectColor;
  final int effectVisibility;
  final int effectScale;
  final bool effectMotion;
  final String theme;
  final String color;
  final String receivedColor;
  final int receivedVisibility;
  final String shape;
  final int visibility;
  final String composerColor;
  final int composerVisibility;
  final String composerShape;
  final bool composerOutline;
  final String background;
  final String preset;
  final int dim;
  final int blur;
  final String fit;
  final bool motion;
  final bool focus;
  const ChatAppearance({
    this.effect = 'contour',
    this.effectColor = '#22d3ee',
    this.effectVisibility = 20,
    this.effectScale = 85,
    this.effectMotion = true,
    this.theme = 'classic',
    this.color = '#3b82f6',
    this.receivedColor = 'auto',
    this.receivedVisibility = 40,
    this.shape = 'classic',
    this.visibility = 50,
    this.composerColor = 'auto',
    this.composerVisibility = 50,
    this.composerShape = 'soft',
    this.composerOutline = false,
    this.background = 'preset',
    this.preset = 'waves',
    this.dim = 0,
    this.blur = 0,
    this.fit = 'cover',
    this.motion = true,
    this.focus = false,
  });
  Map<String, dynamic> toJson() => {
        'effect': effect,
        'effectColor': effectColor,
        'effectVisibility': effectVisibility,
        'effectScale': effectScale,
        'effectMotion': effectMotion,
        'theme': theme,
        'color': color,
        'receivedColor': receivedColor,
        'receivedVisibility': receivedVisibility,
        'shape': shape,
        'visibility': visibility,
        'composerColor': composerColor,
        'composerVisibility': composerVisibility,
        'composerShape': composerShape,
        'composerOutline': composerOutline,
        'background': background,
        'preset': preset,
        'dim': dim,
        'blur': blur,
        'fit': fit,
        'motion': motion,
        'focus': focus,
      };
}

const defaultAppearance = ChatAppearance();
int _clamp(dynamic v, int min, int max, int fb) =>
    (v is num && v.isFinite) ? v.toInt().clamp(min, max) : fb;
ChatAppearance normalizeAppearance(dynamic value) {
  if (value is! Map) return defaultAppearance;
  final v = Map<String, dynamic>.from(value as Map);
  String eff = v['effect'] as String? ?? 'none';
  if (!['flow', 'contour', 'arcade'].contains(eff)) eff = 'none';
  String ec = v['effectColor'] as String? ?? 'auto';
  if (ec != 'auto' && !RegExp(r'^#[\da-fA-F]{6}$').hasMatch(ec)) ec = 'auto';
  String col = v['color'] as String? ?? defaultAppearance.color;
  if (!RegExp(r'^#[\da-fA-F]{6}$').hasMatch(col)) col = defaultAppearance.color;
  String rc = v['receivedColor'] as String? ?? 'auto';
  if (rc != 'auto' && !RegExp(r'^#[\da-fA-F]{6}$').hasMatch(rc)) rc = 'auto';
  String cc = v['composerColor'] as String? ?? 'auto';
  if (cc != 'auto' && !RegExp(r'^#[\da-fA-F]{6}$').hasMatch(cc)) cc = 'auto';
  String th = v['theme'] as String? ?? 'classic';
  if (!chatThemes.any((t) => t.$1 == th)) th = 'classic';
  String shape = v['shape'] as String? ?? 'classic';
  if (!['soft', 'capsule'].contains(shape)) shape = 'classic';
  String cs = v['composerShape'] as String? ?? 'pill';
  if (cs != 'soft') cs = 'pill';
  String bg = v['background'] as String? ?? 'original';
  if (!['solid', 'preset', 'upload'].contains(bg)) bg = 'original';
  String preset = v['preset'] as String? ?? 'breathe';
  if (!['aurora', 'waves'].contains(preset)) preset = 'breathe';
  String fit = v['fit'] as String? ?? 'cover';
  if (!['contain', 'repeat'].contains(fit)) fit = 'cover';
  return ChatAppearance(
    effect: eff,
    effectColor: ec,
    effectVisibility: _clamp(v['effectVisibility'], 0, 100, 18),
    effectScale: _clamp(v['effectScale'], 60, 180, 100),
    effectMotion: v['effectMotion'] == true,
    theme: th,
    color: col,
    receivedColor: rc,
    receivedVisibility: _clamp(v['receivedVisibility'], 35, 100, 100),
    shape: shape,
    visibility: _clamp(v['visibility'], 35, 100, 100),
    composerColor: cc,
    composerVisibility: _clamp(v['composerVisibility'], 35, 100, 100),
    composerShape: cs,
    composerOutline: v['composerOutline'] == true,
    background: bg,
    preset: preset,
    dim: _clamp(v['dim'], 0, 85, 20),
    blur: _clamp(v['blur'], 0, 12, 0),
    fit: fit,
    motion: v['motion'] != false,
    focus: v['focus'] == true,
  );
}

Color _hex(String s) =>
    Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));
Color composerEffectiveColor(ChatAppearance p, TRColors c) {
  if (p.composerColor == 'auto') {
    final light = c.bg.computeLuminance() > 0.5;
    return light ? Colors.white : const Color(0xFF000000);
  }
  return _hex(p.composerColor);
}

double composerStrength(ChatAppearance p) =>
    p.composerVisibility.clamp(0, 100) / 100.0;
double composerRadius(ChatAppearance p) => p.composerShape == 'soft' ? 18 : 28;
Color? composerBorder(ChatAppearance p, TRColors c) =>
    p.composerOutline ? c.border.withValues(alpha: .7) : null;
Color composerOnColor(ChatAppearance p, TRColors c) {
  if (p.composerColor == 'auto' || p.composerVisibility < 75) return c.text1;
  return TRAccent.on(_hex(p.composerColor));
}

class ChatAppearanceStore extends ChangeNotifier {
  final String userId;
  final String chatId;
  ChatAppearance _value = defaultAppearance;
  bool _customized = false;
  ChatAppearance get value => _value;

  /// False until the user saves a theme for this chat; the chat keeps its
  /// original look until then (and again after Reset).
  bool get customized => _customized;
  String get _key => 'tr.chat-theme.$userId.$chatId';

  /// Every open store per chat, so a change in the theme page shows up in the
  /// open chat immediately instead of after reopening it.
  static final Map<String, Set<ChatAppearanceStore>> _live = {};
  bool _disposed = false;

  ChatAppearanceStore(this.userId, this.chatId) {
    (_live[_key] ??= {}).add(this);
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && !_disposed) {
        _value = normalizeAppearance(jsonDecode(raw));
        _customized = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _broadcast() {
    for (final s in [...?_live[_key]]) {
      if (s._disposed) continue;
      s._value = _value;
      s._customized = _customized;
      s.notifyListeners();
    }
  }

  Future<void> patch(Map<String, dynamic> p) async {
    _value = normalizeAppearance({..._value.toJson(), ...p});
    _customized = true;
    _broadcast();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(_value.toJson()));
    } catch (_) {}
  }

  Future<void> reset() async {
    _value = defaultAppearance;
    _customized = false;
    _broadcast();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_key);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _live[_key]?.remove(this);
    if (_live[_key]?.isEmpty ?? false) _live.remove(_key);
    super.dispose();
  }
}

/// Gradient colors for the background presets.
List<Color> chatPresetGradient(String p) {
  switch (p) {
    case 'aurora':
      return const [Color(0xFF0B1E3A), Color(0xFF1F3A8A), Color(0xFF3A1F8A)];
    case 'waves':
      return const [Color(0xFF0A1A2B), Color(0xFF0F2746), Color(0xFF0A1A2B)];
    default:
      return const [Color(0xFF312E81), Color(0xFF0B0B14)];
  }
}

/// Bubble corner radius for the chosen shape.
double chatBubbleRadius(ChatAppearance p) =>
    p.shape == 'capsule' ? 26 : (p.shape == 'soft' ? 20 : 14);

/// My bubble color, or null when it isn't customized.
Color? chatMineColor(ChatAppearance p, Color surface) {
  try {
    final base = _hex(p.color);
    return Color.alphaBlend(
        base.withValues(alpha: p.visibility / 100), surface);
  } catch (_) {
    return null;
  }
}

/// Received bubble color, or null for the original.
Color? chatReceivedColor(ChatAppearance p, Color surface) {
  if (p.receivedColor == 'auto') return null;
  try {
    return Color.alphaBlend(
        _hex(p.receivedColor).withValues(alpha: p.receivedVisibility / 100),
        surface);
  } catch (_) {
    return null;
  }
}
