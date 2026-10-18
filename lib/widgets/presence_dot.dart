import 'package:flutter/material.dart';

/// Port of `src/components/ui/presence-dot.tsx`.
///
/// Small status dot indicating online/offline. Hidden when offline unless
/// [showOffline] is true.
class PresenceDot extends StatelessWidget {
  final bool online;
  final bool showOffline;
  final double size;
  final double ringWidth;

  const PresenceDot({
    super.key,
    required this.online,
    this.showOffline = false,
    this.size = 10,
    this.ringWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (!online && !showOffline) return const SizedBox.shrink();
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Semantics(
      label: online ? 'Online' : 'Offline',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: online
              ? const Color(0xFF34D399)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: .35),
          border: Border.all(color: bg, width: ringWidth),
          boxShadow: online
              ? [
                  BoxShadow(
                    color: const Color(0xFF34D399).withValues(alpha: .45),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
