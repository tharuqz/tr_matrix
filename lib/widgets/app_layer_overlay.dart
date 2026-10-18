import 'package:flutter/material.dart';

/// MaterialApp.builder is above the router's Navigator/Overlay. Global UI
/// needs an Overlay ancestor of its own for ink reactions and tooltips.
/// Keep the router child in the same entry so its Navigator stays unchanged.
class AppLayerOverlay extends StatefulWidget {
  final Widget child;
  const AppLayerOverlay({super.key, required this.child});

  @override
  State<AppLayerOverlay> createState() => _AppLayerOverlayState();
}

class _AppLayerOverlayState extends State<AppLayerOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => SizedBox.expand(child: widget.child),
  );

  @override
  void didUpdateWidget(covariant AppLayerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The inherited configuration and child may change while the entry is
    // retained. Refresh after the current tree has finished building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry.mounted) _entry.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
