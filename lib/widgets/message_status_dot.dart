import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// Port of `src/components/chat/message-status-dot.tsx`.
///
/// 4 states (all 8px, `seen` has a 3px core):
///  1. sending/hollow ring (pending)
///  2. sent → muted outline fill
///  3. delivered → sky-400 ring
///  4. seen → sky ring + 3px solid core
class MessageStatusDot extends StatelessWidget {
  final bool pending;
  final bool delivered;
  final bool seen;
  const MessageStatusDot({
    super.key,
    required this.pending,
    required this.delivered,
    required this.seen,
  });

  @override
  Widget build(BuildContext context) {
    // pending (hollow ring) — matches web `sending: hollow ring`
    if (pending) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF9CA3AF), width: 1.2),
        ),
      );
    }
    if (seen) {
      // sky ring + 3px core (TRApp receiptSeen / receiptDelivered palette)
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: TRAccent.receiptDelivered, width: 1.2),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 3,
          height: 3,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: TRAccent.receiptDelivered,
          ),
        ),
      );
    }
    if (delivered) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: TRAccent.receiptDelivered,
        ),
      );
    }
    // sent: muted filled dot (matches web `sent: muted filled`)
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF9CA3AF),
      ),
    );
  }
}

/// Backwards-compatible alias used in some chat bubbles.
class ReceiptTicks extends StatelessWidget {
  final bool pending;
  final bool delivered;
  final bool seen;
  const ReceiptTicks({
    super.key,
    required this.pending,
    required this.delivered,
    required this.seen,
  });
  @override
  Widget build(BuildContext context) =>
      MessageStatusDot(pending: pending, delivered: delivered, seen: seen);
}
