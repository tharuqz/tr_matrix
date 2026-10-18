import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/models.dart';
import '../data/pinned_repository.dart';

/// Port of `src/components/chat/pinned-banner.tsx`.
///
/// Sticky top-0, `border-b border-white/5 bg-black/65 backdrop-blur-xl`,
/// `Pin` sky-400 + `Pinned message · N` + truncated preview + X unpin.
/// Tapping jumps via `onJump`, X calls `onUnpin`. `Frosted` to avoid overflows
/// at 360dp (Flexible/Expanded per safeguards).
class PinnedBanner extends StatelessWidget {
  final List<PinnedRow> pins;
  final List<Message> messages;
  final void Function(String messageId) onJump;
  final void Function(String messageId) onUnpin;
  const PinnedBanner({
    super.key,
    required this.pins,
    required this.messages,
    required this.onJump,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    if (pins.isEmpty) return const SizedBox.shrink();
    final current = pins.first;
    final msg = messages
        .where((m) => m.id == current.messageId)
        .cast<Message?>()
        .firstOrNull;
    final preview = pinnedPreview(msg);
    final c = context.tr;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onJump(current.messageId),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: Color(0xFF38BDF8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              pins.length > 1
                                  ? 'Pinned message · ${pins.length}'
                                  : 'Pinned message',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => onUnpin(current.messageId),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Icon(Icons.close_rounded, size: 14, color: c.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
