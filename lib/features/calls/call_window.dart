import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';

/// Desktop call window: a separate, draggable, resizable panel floating over
/// the app (like Telegram Desktop / WhatsApp for PC). The chats behind stay
/// usable. Double-click the title bar or press the expand button to fill the
/// window; drag the bottom-right corner to resize.
class CallWindow extends StatefulWidget {
  final String title;
  final Widget child;
  final Size initialSize;
  final VoidCallback? onMinimize;
  final bool allowExpand;
  const CallWindow({
    super.key,
    required this.title,
    required this.child,
    this.initialSize = const Size(720, 480),
    this.onMinimize,
    this.allowExpand = true,
  });
  @override
  State<CallWindow> createState() => _CallWindowState();
}

class _CallWindowState extends State<CallWindow> {
  static Offset? _savedPos;
  static Size? _savedSize;
  Offset? _pos;
  late Size _size = _savedSize ?? widget.initialSize;
  bool _expanded = false;

  Rect _clamp(Size screen) {
    final w = _size.width.clamp(340.0, screen.width - 16).toDouble();
    final h = _size.height.clamp(260.0, screen.height - 16).toDouble();
    final p = _pos ??
        _savedPos ??
        Offset((screen.width - w) / 2, (screen.height - h) / 2);
    return Rect.fromLTWH(
      p.dx.clamp(8.0, (screen.width - w - 8).clamp(8.0, double.infinity)),
      p.dy.clamp(8.0, (screen.height - h - 8).clamp(8.0, double.infinity)),
      w,
      h,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return LayoutBuilder(builder: (context, box) {
      final screen = box.biggest;
      final r = _expanded ? Offset.zero & screen : _clamp(screen);
      final bar = GestureDetector(
        onDoubleTap: widget.allowExpand
            ? () => setState(() => _expanded = !_expanded)
            : null,
        onPanUpdate: _expanded
            ? null
            : (d) => setState(() {
                  _pos = r.topLeft + d.delta;
                  _savedPos = _pos;
                }),
        child: MouseRegion(
          cursor: _expanded ? MouseCursor.defer : SystemMouseCursors.move,
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 12, right: 4),
            color: c.surface2,
            child: Row(children: [
              Icon(Icons.call_rounded, size: 14, color: context.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TRText.body(12, c.text2, w: FontWeight.w600)),
              ),
              if (widget.onMinimize != null)
                _BarBtn(Icons.remove_rounded, 'Minimize', widget.onMinimize!),
              if (widget.allowExpand)
                _BarBtn(
                    _expanded
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    _expanded ? 'Restore' : 'Fill window',
                    () => setState(() => _expanded = !_expanded)),
            ]),
          ),
        ),
      );
      return Stack(children: [
        Positioned.fromRect(
          rect: r,
          child: Material(
            elevation: 24,
            color: c.bg,
            borderRadius: BorderRadius.circular(_expanded ? 0 : 14),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                border: _expanded ? null : Border.all(color: c.border),
                borderRadius: BorderRadius.circular(_expanded ? 0 : 14),
              ),
              child: Column(children: [
                bar,
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    removeLeft: true,
                    removeRight: true,
                    child: widget.child,
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (!_expanded)
          Positioned(
            left: r.right - 18,
            top: r.bottom - 18,
            width: 18,
            height: 18,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeDownRight,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  _pos = r.topLeft;
                  _size = Size(r.width + d.delta.dx, r.height + d.delta.dy);
                  _savedSize = _size;
                }),
                child: Icon(Icons.drag_handle_rounded,
                    size: 14, color: c.text3),
              ),
            ),
          ),
      ]);
    });
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _BarBtn(this.icon, this.tip, this.onTap);
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 34,
            height: 28,
            child: Icon(icon, size: 16, color: context.tr.text2),
          ),
        ),
      );
}
