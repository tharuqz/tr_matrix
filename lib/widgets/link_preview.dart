import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

final _urlRe = RegExp(r'https?://[^\s]+', caseSensitive: false);

List<String> extractUrls(String text) =>
    _urlRe.allMatches(text).map((m) => m.group(0)!).toList();

/// Renders text with tappable links + a compact preview card per URL.
/// No extra deps; uses url_launcher already in the project.
class LinkifyText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? linkColor;
  const LinkifyText(this.text, {super.key, this.style, this.linkColor});

  @override
  Widget build(BuildContext context) {
    final urls = extractUrls(text);
    if (urls.isEmpty) return Text(text, style: style);
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _urlRe.allMatches(text)) {
      if (m.start > i) {
        spans.add(TextSpan(text: text.substring(i, m.start), style: style));
      }
      final url = m.group(0)!;
      spans.add(
        WidgetSpan(
          child: GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }
            },
            child: Text(
              url,
              style: (style ?? const TextStyle()).copyWith(
                color: linkColor ?? context.accent,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      );
      i = m.end;
    }
    if (i < text.length) {
      spans.add(TextSpan(text: text.substring(i), style: style));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class LinkPreviewCard extends StatelessWidget {
  final String url;
  const LinkPreviewCard({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? url;
    return GestureDetector(
      onTap: () async {
        final u = Uri.tryParse(url);
        if (u != null) {
          try {
            await launchUrl(u, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(TRRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(Icons.link_rounded, size: 18, color: c.text2),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TRText.body(12, c.text1, w: FontWeight.w600),
                  ),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TRText.body(11, c.text2),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 16, color: c.text3),
          ],
        ),
      ),
    );
  }
}

/// Single + double tick. Reads from message_receipts if locally cached,
/// falls back to delivered-only after send.
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
  Widget build(BuildContext context) {
    final c = context.tr;
    IconData icon;
    Color color;
    if (pending) {
      icon = Icons.schedule_rounded;
      color = c.text3;
    } else if (seen) {
      icon = Icons.done_all_rounded;
      color = context.accent;
    } else if (delivered) {
      icon = Icons.done_all_rounded;
      color = c.text3;
    } else {
      icon = Icons.done_rounded;
      color = c.text3;
    }
    return Icon(icon, size: 14, color: color);
  }
}
