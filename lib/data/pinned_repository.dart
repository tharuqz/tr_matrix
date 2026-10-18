import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Row mirroring `public.pinned_messages` (and local cache shape).
class PinnedRow {
  final String chatId;
  final String messageId;
  final String? pinnedBy;
  final DateTime pinnedAt;
  const PinnedRow({
    required this.chatId,
    required this.messageId,
    this.pinnedBy,
    required this.pinnedAt,
  });

  factory PinnedRow.fromJson(Map<String, dynamic> j) => PinnedRow(
        chatId: j['chat_id'] as String,
        messageId: j['message_id'] as String,
        pinnedBy: j['pinned_by'] as String?,
        pinnedAt: DateTime.tryParse(j['pinned_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'chat_id': chatId,
        'message_id': messageId,
        'pinned_by': pinnedBy,
        'pinned_at': pinnedAt.toUtc().toIso8601String(),
      };
}

/// Port of `src/hooks/use-pinned-messages.ts` (max 3, realtime `pinned:<chatId>`).
///
/// Combines Supabase `pinned_messages` with local fallbacks so offline viewing
/// is instant. Realtime is subscribed via `subscribePinned`; local cache is
/// kept in the chat repository's OfflineStore under `pinned:<chatId>` for parity.
class PinnedRepository {
  static const maxPins = 3;
  final SupabaseClient db;
  final String ownerId;

  PinnedRepository(this.db, this.ownerId);

  Future<List<PinnedRow>> fetchPins(String chatId) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await db
            .from('pinned_messages')
            .select('chat_id, message_id, pinned_by, pinned_at')
            .eq('chat_id', chatId)
            .order('pinned_at', ascending: false),
      );
      return rows.map(PinnedRow.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  /// Evicts oldest when at cap (client-side enforcement matching web).
  Future<void> pin(String chatId, String messageId) async {
    final existing = await fetchPins(chatId);
    if (existing.length >= maxPins) {
      final oldest = existing.last;
      try {
        await db
            .from('pinned_messages')
            .delete()
            .eq('chat_id', chatId)
            .eq('message_id', oldest.messageId);
      } catch (_) {}
    }
    try {
      await db.from('pinned_messages').insert({
        'chat_id': chatId,
        'message_id': messageId,
        'pinned_by': ownerId,
      });
    } catch (_) {
      // best-effort: table may not yet exist (migration pending)
    }
  }

  Future<void> unpin(String chatId, String messageId) async {
    try {
      await db
          .from('pinned_messages')
          .delete()
          .eq('chat_id', chatId)
          .eq('message_id', messageId);
    } catch (_) {}
  }

  RealtimeChannel subscribePinned(
    String chatId,
    void Function(PinnedRow row, String event) onEvent,
  ) {
    return db
        .channel('pinned:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pinned_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            final rec = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            if (rec.isEmpty) return;
            final row = PinnedRow.fromJson(rec);
            final ev = payload.eventType.name; // insert/delete/update
            onEvent(row, ev);
          },
        )
        .subscribe();
  }
}

/// Helper to strip fancy markers for preview (port of `stripFancy` usage in
/// `pinned-banner.tsx:23` and web search highlights).
String stripFancyForPreview(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  // Remove the `U+2064` 24-bit color wrapper and `U+2063×2 N×U+200C` fx wrapper.
  // Keep it simple: strip those control chars and leave readable text.
  var s = raw;
  // color wrapper: U+2064 + 24 bits (U+200B/U+200C) + U+2064
  s = s.replaceAll(RegExp('\u2064[\u200B\u200C]{24}\u2064'), '');
  // fx wrapper: U+2063 U+2063 (U+200C){1,8} U+2063
  s = s.replaceAll(RegExp('\u2063\u2063\u200C+\u2063'), '');
  return s;
}

String pinnedPreview(Message? msg) {
  if (msg == null) return 'Pinned message';
  if (msg.deleted) return '(deleted message)';
  final c = stripFancyForPreview(msg.content);
  if (c.trim().isNotEmpty) return c;
  if (msg.mediaName != null && msg.mediaName!.isNotEmpty)
    return '📎 ${msg.mediaName}';
  if ((msg.mediaType ?? '').startsWith('image/')) return '📷 Photo';
  if ((msg.mediaType ?? '').startsWith('audio/')) return '🎤 Voice note';
  return 'Attachment';
}
