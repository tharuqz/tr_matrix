import 'dart:async';
import 'package:flutter/material.dart';
import '../core/realtime/live_status.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// "Online" with a green dot, or the real "last seen …" for a person.
class LastSeenText extends StatefulWidget {
  final String? userId;
  final TextStyle? style;
  final bool center;
  const LastSeenText({
    super.key,
    required this.userId,
    this.style,
    this.center = false,
  });
  @override
  State<LastSeenText> createState() => _LastSeenTextState();
}

class _LastSeenTextState extends State<LastSeenText> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep "5m ago" fresh.
    // Keep "5m ago" fresh and re-check the server's last seen every minute.
    var n = 0;
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (++n % 2 == 0) _load();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LastSeenText old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  void _load() {
    final id = widget.userId;
    if (id != null) LiveStatus.instance.loadLastSeen([id]);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return ListenableBuilder(
      listenable: LiveStatus.instance,
      builder: (_, __) {
        final id = widget.userId;
        final live = LiveStatus.instance;
        final online = id != null && live.isOnline(id);
        final label = id == null
            ? ''
            : (online ? 'Online' : formatLastSeen(live.lastSeen(id)));
        return Row(
          mainAxisSize: widget.center ? MainAxisSize.min : MainAxisSize.max,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: online ? c.success : c.text3.withValues(alpha: .5),
                shape: BoxShape.circle,
                boxShadow: online
                    ? [
                        BoxShadow(
                          color: c.success.withValues(alpha: .5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.style ?? TRText.body(12, c.text3),
              ),
            ),
          ],
        );
      },
    );
  }
}
