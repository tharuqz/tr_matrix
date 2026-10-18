import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tokens.dart';

enum TRThemeMode { dark, amoled, light }

/// Holds the user's appearance + accessibility choices and saves them on the device.
class ThemeController extends ChangeNotifier {
  TRThemeMode mode = TRThemeMode.dark;
  bool followSystem = false;
  Color accent = TRAccent.defaultAccent;
  String fontSize = 'medium'; // small | medium | large
  bool reducedMotion = false;
  bool compact = false;
  bool hidePreviews = false;

  double get textScale => switch (fontSize) {
        'small' => .9,
        'large' => 1.15,
        _ => 1.0,
      };

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode = TRThemeMode.values.firstWhere(
      (m) => m.name == p.getString('tr.mode'),
      orElse: () => TRThemeMode.dark,
    );
    followSystem = p.getBool('tr.system') ?? false;
    final a = p.getInt('tr.accent');
    if (a != null) accent = Color(a);
    fontSize = p.getString('tr.fontSize') ?? 'medium';
    reducedMotion = p.getBool('tr.reducedMotion') ?? false;
    compact = p.getBool('tr.compact') ?? false;
    hidePreviews = p.getBool('tr.hidePreviews') ?? false;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tr.mode', mode.name);
    await p.setBool('tr.system', followSystem);
    await p.setInt('tr.accent', accent.toARGB32());
    await p.setString('tr.fontSize', fontSize);
    await p.setBool('tr.reducedMotion', reducedMotion);
    await p.setBool('tr.compact', compact);
    await p.setBool('tr.hidePreviews', hidePreviews);
  }

  void _set(void Function() f) {
    f();
    notifyListeners();
    _save();
  }

  void setMode(TRThemeMode m) => _set(() {
        mode = m;
        followSystem = false;
      });
  void setFollowSystem(bool v) => _set(() => followSystem = v);
  void setAccent(Color c) => _set(() => accent = c);
  void setFontSize(String v) => _set(() => fontSize = v);
  void setReducedMotion(bool v) => _set(() => reducedMotion = v);
  void setCompact(bool v) => _set(() => compact = v);
  void setHidePreviews(bool v) => _set(() => hidePreviews = v);

  TRThemeMode get effectiveMode {
    if (!followSystem) return mode;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.light
        ? TRThemeMode.light
        : TRThemeMode.dark;
  }

  TRColors get colors => switch (effectiveMode) {
        TRThemeMode.dark => TRColors.dark,
        TRThemeMode.amoled => TRColors.amoled,
        TRThemeMode.light => TRColors.light,
      };
}

/// Theme extension so any widget can read `context.tr.surface2` etc.
class TRTheme extends ThemeExtension<TRTheme> {
  final TRColors c;
  final Color accent;
  const TRTheme(this.c, this.accent);

  @override
  TRTheme copyWith({TRColors? c, Color? accent}) =>
      TRTheme(c ?? this.c, accent ?? this.accent);
  @override
  TRTheme lerp(TRTheme? other, double t) => other ?? this;
}

extension TRContext on BuildContext {
  TRColors get tr => Theme.of(this).extension<TRTheme>()?.c ?? TRColors.dark;
  Color get accent =>
      Theme.of(this).extension<TRTheme>()?.accent ?? TRAccent.defaultAccent;
}

/// Typography: Sora (display), Manrope (body), JetBrains Mono.
class TRText {
  static TextStyle display(
    double size,
    Color color, {
    FontWeight w = FontWeight.w700,
  }) =>
      TextStyle(
        fontFamily: 'Sora',
        fontSize: size,
        fontWeight: w,
        color: color,
        letterSpacing: 0,
        height: 1.2,
      );
  static TextStyle body(
    double size,
    Color color, {
    FontWeight w = FontWeight.w400,
  }) =>
      TextStyle(
        fontFamily: 'Manrope',
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.45,
      );
  static TextStyle mono(double size, Color color) => TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: size,
        color: color,
        letterSpacing: 0,
      );
}

ThemeData buildTheme(ThemeController ctl) {
  final c = ctl.colors;
  final brightness = ctl.effectiveMode == TRThemeMode.light
      ? Brightness.light
      : Brightness.dark;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: NoSplash.splashFactory, // web feel: no ripples
    visualDensity: ctl.compact ? VisualDensity.compact : VisualDensity.standard,
    highlightColor: Colors.transparent,
    hoverColor: c.text1.withValues(alpha: .05),
    colorScheme: ColorScheme.fromSeed(
      seedColor: ctl.accent,
      brightness: brightness,
      surface: c.surface1,
      primary: ctl.accent,
      onPrimary: TRAccent.on(ctl.accent),
      error: c.danger,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Manrope',
      bodyColor: c.text1,
      displayColor: c.text1,
    ),
    dividerColor: c.border,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: c.surface2,
      selectedColor: ctl.accent.withValues(alpha: .16),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TRText.body(13, c.text2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface1,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TRRadius.glass),
        ),
      ),
    ),
    // Visible, web-style thin scrollbars.
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(true),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(999),
      thumbColor: WidgetStatePropertyAll(c.text1.withValues(alpha: .18)),
      crossAxisMargin: 2,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surface3,
        borderRadius: BorderRadius.circular(TRRadius.md),
        border: Border.all(color: c.border),
      ),
      textStyle: TRText.body(12, c.text1, w: FontWeight.w500),
      waitDuration: const Duration(milliseconds: 400),
    ),
    extensions: [TRTheme(c, ctl.accent)],
  );
}
