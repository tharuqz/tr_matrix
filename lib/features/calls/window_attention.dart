import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Pops the desktop window to the front when a call rings (like Telegram),
/// and releases "always on top" once answered / ended.
class WindowAttention {
  static bool _ready = false;
  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static Future<void> init() async {
    if (!_desktop) return;
    try {
      await windowManager.ensureInitialized();
      _ready = true;
    } catch (e) {
      debugPrint('[window] $e');
    }
  }

  static Future<void> ring() async {
    if (!_ready) return;
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
    } catch (e) {
      debugPrint('[window] $e');
    }
  }

  static Future<void> calm() async {
    if (!_ready) return;
    try {
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {}
  }
}
