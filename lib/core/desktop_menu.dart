import 'desktop_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Computer-style menus.
///
/// On Windows / macOS / Linux (and wide web windows) menus open as a small
/// rounded box right next to the mouse instead of sliding up from the bottom
/// middle like a phone. Phones keep the normal bottom sheet.
class PointerTracker {
  PointerTracker._();
  static Offset last = Offset.zero;
  static bool _on = false;

  /// Call once at startup.
  static void install() {
    if (_on) return;
    _on = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent || e is PointerHoverEvent) last = e.position;
    });
  }
}

bool get _desktopPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

/// True when menus should be compact popups instead of bottom sheets.
bool useDesktopMenus(BuildContext context) =>
    _desktopPlatform && MediaQuery.sizeOf(context).width >= 600;

/// Same arguments as [showModalBottomSheet]. On computers it shows a compact
/// popup next to the mouse ([large] = a centered panel for big settings pages).
Future<T?> showAnchoredSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = false,
  Color? barrierColor,
  bool useRootNavigator = false,
  bool large = false,
  Offset? at,
}) {
  if (!useDesktopMenus(context)) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      constraints: constraints,
      isScrollControlled: isScrollControlled,
      shape: shape,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      barrierColor: barrierColor,
      useRootNavigator: useRootNavigator,
    );
  }
  final anchor = at ?? PointerTracker.last;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: isDismissible,
    barrierLabel: 'Close menu',
    barrierColor: large ? Colors.black38 : Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, __) {
      final screen = MediaQuery.sizeOf(ctx);
      final w = large ? (screen.width - 48).clamp(320.0, 480.0) : 290.0;
      final h = large
          ? (screen.height * .86).clamp(320.0, 820.0)
          : (screen.height - 24).clamp(200.0, 560.0);
      final bg = backgroundColor == null || backgroundColor.a == 0
          ? Theme.of(ctx).colorScheme.surface
          : backgroundColor;
      final card = Material(
        color: large ? bg : Colors.transparent,
        elevation: large ? 18 : 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: MediaQuery.removePadding(
          context: ctx,
          removeBottom: true,
          removeTop: true,
          child: large
              ? SizedBox(width: w, height: h, child: builder(ctx))
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: w, maxHeight: h),
                  child: SingleChildScrollView(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black38,
                              blurRadius: 24,
                              offset: Offset(0, 8)),
                        ],
                      ),
                      child: builder(ctx),
                    ),
                  ),
                ),
        ),
      );
      if (large) return Center(child: card);
      return CustomSingleChildLayout(
        delegate: _NearPointer(anchor),
        child: card,
      );
    },
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: .94, end: 1.0)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
  );
}

/// Places the popup at the mouse, flipping left/up when it would leave the window.
class _NearPointer extends SingleChildLayoutDelegate {
  final Offset p;
  _NearPointer(this.p);
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(Size(c.maxWidth - 16, c.maxHeight - 16));
  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = p.dx + 4, y = p.dy + 4;
    if (x + child.width > size.width - 8) x = p.dx - child.width - 4;
    if (y + child.height > size.height - 8) y = size.height - child.height - 8;
    final maxX = size.width - child.width - 8, maxY = size.height - child.height - 8;
    return Offset(x.clamp(8.0, maxX < 8 ? 8.0 : maxX), y.clamp(8.0, maxY < 8 ? 8.0 : maxY));
  }

  @override
  bool shouldRelayout(_NearPointer old) => old.p != p;
}
