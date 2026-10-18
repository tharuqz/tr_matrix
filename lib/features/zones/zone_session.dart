import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'zone_controller.dart';

/// Keeps one Zone alive while you browse the rest of the app.
/// The Zone page borrows the controller; leaving the page while joined keeps
/// you in the Zone and shows the floating Zone bar instead.
class ActiveZone {
  final ZoneController controller;
  final String chatId, title;
  DateTime? joinedAt;
  ActiveZone(this.controller, this.chatId, this.title);
}

class ZoneSession {
  ZoneSession._();

  /// Navigator used by the floating bar to re-open the Zone page.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// The Zone you are currently joined to (null when not in a Zone).
  static final active = ValueNotifier<ActiveZone?>(null);

  /// True while the Zone page is on screen (the bar hides then).
  static final pageOpen = ValueNotifier<bool>(false);

  static ActiveZone? _current;

  static ActiveZone obtain(String chatId, String title) {
    final cur = _current;
    if (cur != null && cur.chatId == chatId) return cur;
    // Opening another chat's Zone: leave the old one first.
    if (cur != null) _drop(cur);
    final s = ActiveZone(
      ZoneController(Supabase.instance.client, chatId),
      chatId,
      title,
    );
    void sync() {
      final z = s.controller;
      if (z.joined) {
        s.joinedAt ??= DateTime.now();
        if (active.value != s) active.value = s;
      } else {
        s.joinedAt = null;
        if (active.value == s) active.value = null;
        if (!pageOpen.value && _current == s) _drop(s);
      }
    }

    s.controller.addListener(sync);
    _current = s;
    return s;
  }

  /// Called when the Zone page closes. Keeps the Zone if still joined.
  static void release(ActiveZone s) {
    if (s.controller.joined) return;
    if (_current == s) _drop(s);
  }

  static Future<void> leave() async {
    final s = _current;
    if (s == null) return;
    await s.controller.leave();
    if (!pageOpen.value && _current == s) _drop(s);
  }

  static void _drop(ActiveZone s) {
    if (active.value == s) active.value = null;
    _current = null;
    s.controller.dispose();
  }
}

String formatZoneElapsed(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String p(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(sec)}' : '${p(m)}:${p(sec)}';
}
