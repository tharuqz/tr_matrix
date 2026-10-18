import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../features/zones/zone_session.dart';

/// Port of src/components/zones/zone-button.tsx — the website's "Radio"
/// broadcast icon (dot + waves). Waves pulse and the people count glows when
/// someone is in the Zone.
class ZoneButton extends StatefulWidget {
  final int count;
  final bool joined;
  final bool screenSharing;
  final bool recording;
  final VoidCallback onPressed;
  const ZoneButton({
    super.key,
    required this.count,
    required this.joined,
    this.screenSharing = false,
    this.recording = false,
    required this.onPressed,
  });

  @override
  State<ZoneButton> createState() => _ZoneButtonState();
}

class _ZoneButtonState extends State<ZoneButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _live => widget.count > 0 || widget.joined;

  @override
  void initState() {
    super.initState();
    if (_live) _a.repeat();
  }

  @override
  void didUpdateWidget(covariant ZoneButton old) {
    super.didUpdateWidget(old);
    if (_live && !_a.isAnimating) _a.repeat();
    if (!_live && _a.isAnimating) _a.stop();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final c = context.tr;
    final reduce = MediaQuery.of(context).disableAnimations;
    final col = _live ? accent : c.text2;
    return Tooltip(
      message: widget.joined
          ? 'Joined Zone'
          : widget.count > 0
              ? 'Join Zone (${widget.count} inside)'
              : 'Open Zone',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(TRRadius.pill),
          child: AnimatedBuilder(
            animation: _a,
            builder: (_, __) {
              final t = reduce ? 0.5 : _a.value;
              final glow =
                  _live ? (0.35 + 0.35 * math.sin(t * math.pi * 2).abs()) : 0.0;
              return Container(
                height: 44,
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(TRRadius.pill),
                  color: widget.joined
                      ? accent.withValues(alpha: .14)
                      : Colors.transparent,
                  border: widget.joined
                      ? Border.all(color: accent.withValues(alpha: .5))
                      : null,
                  boxShadow: widget.joined
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: glow * .5),
                            blurRadius: 14,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CustomPaint(
                        painter: _RadioPainter(
                          color: col,
                          t: t,
                          live: _live && !reduce,
                        ),
                      ),
                    ),
                    if (widget.count > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(TRRadius.pill),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: glow),
                              blurRadius: 10,
                              spreadRadius: .5,
                            ),
                          ],
                        ),
                        child: Text(
                          '${widget.count}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: accent,
                            shadows: [
                              Shadow(
                                color: accent.withValues(alpha: glow),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (widget.screenSharing) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.screen_share_rounded, size: 12, color: accent),
                    ],
                    if (widget.recording) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.fiber_manual_record_rounded,
                        size: 12,
                        color: c.danger,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// lucide "Radio": centre dot with an inner and outer wave on each side.
class _RadioPainter extends CustomPainter {
  final Color color;
  final double t;
  final bool live;
  _RadioPainter({required this.color, required this.t, required this.live});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24; // lucide 24-unit grid
    final c = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, 2 * s, Paint()..color = color);
    // Wave opacity ripples outward when live.
    double op(int ring) {
      if (!live) return 1;
      final phase = (t - ring * .25) % 1.0;
      return .45 + .55 * (1 - (phase - .5).abs() * 2).clamp(0.0, 1.0);
    }

    for (final ring in [0, 1]) {
      final r = (ring == 0 ? 5.6 : 9.6) * s;
      stroke.color = color.withValues(alpha: op(ring));
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(rect, -math.pi / 4, math.pi / 2, false, stroke); // right
      canvas.drawArc(rect, math.pi * 3 / 4, math.pi / 2, false, stroke); // left
    }
  }

  @override
  bool shouldRepaint(covariant _RadioPainter o) =>
      o.t != t || o.color != color || o.live != live;
}

/// Header Zone button that watches how many people are in this chat's Zone.
class LiveZoneButton extends StatefulWidget {
  final String chatId;
  final VoidCallback onPressed;
  const LiveZoneButton({
    super.key,
    required this.chatId,
    required this.onPressed,
  });
  @override
  State<LiveZoneButton> createState() => _LiveZoneButtonState();
}

class _LiveZoneButtonState extends State<LiveZoneButton> {
  int _count = 0;
  RealtimeChannel? _ch;
  String? _zoneId;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LiveZoneButton old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId) {
      _unsub();
      _count = 0;
      _zoneId = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final z = await _db
          .from('zones')
          .select('id')
          .eq('chat_id', widget.chatId)
          .maybeSingle();
      if (!mounted || z == null) return;
      _zoneId = z['id'] as String;
      await _refresh();
      _ch = _db
          .channel(
            'zone-count:${widget.chatId}:${DateTime.now().microsecondsSinceEpoch}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'zone_participants',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'zone_id',
              value: _zoneId!,
            ),
            callback: (_) => _refresh(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('[zone] count: $e');
    }
  }

  Future<void> _refresh() async {
    final id = _zoneId;
    if (id == null) return;
    try {
      final rows = await _db
          .from('zone_participants')
          .select('user_id')
          .eq('zone_id', id);
      if (mounted) setState(() => _count = (rows as List).length);
    } catch (_) {}
  }

  void _unsub() {
    if (_ch != null) unawaited(_db.removeChannel(_ch!));
    _ch = null;
  }

  @override
  void dispose() {
    _unsub();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveZone?>(
      valueListenable: ZoneSession.active,
      builder: (_, a, __) {
        final joined = a != null && a.chatId == widget.chatId;
        return ListenableBuilder(
          listenable: joined ? a.controller : ZoneSession.active,
          builder: (_, __) => ZoneButton(
            count: joined ? a.controller.participants.length : _count,
            joined: joined,
            screenSharing: joined && a.controller.sharing,
            onPressed: widget.onPressed,
          ),
        );
      },
    );
  }
}
