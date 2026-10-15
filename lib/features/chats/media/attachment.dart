import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/app_scope.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/chat_actions.dart';
import '../../../data/models.dart';
import 'voice.dart';

String fmtSize(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Shows the photo / sticker / voice note / video / file inside a message.
class Attachment extends StatelessWidget {
  final Message msg;
  final Color fg;
  const Attachment({super.key, required this.msg, required this.fg});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).chats;
    final type = msg.mediaType ?? '';
    final sticker = isStickerName(msg.mediaName);
    return FutureBuilder<String?>(
      future: repo.mediaUrl(msg.mediaUrl),
      builder: (_, snap) {
        final url = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(
              width: sticker ? 160 : 220,
              height: sticker ? 160 : 120,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: fg)));
        }
        if (url == null) return _FileTile(msg: msg, fg: fg, url: null);
        if (sticker) {
          return SizedBox(width: 160, height: 160, child: Image.network(url, fit: BoxFit.contain));
        }
        if (type.startsWith('image/')) {
          return GestureDetector(
            onTap: () => openImageViewer(context, url, msg.mediaName),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TRRadius.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320, maxWidth: 320, minWidth: 120),
                child: Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _FileTile(msg: msg, fg: fg, url: url)),
              ),
            ),
          );
        }
        if (type.startsWith('audio/')) return VoiceNotePlayer(url: url, fg: fg);
        return _FileTile(msg: msg, fg: fg, url: url);
      },
    );
  }
}

class _FileTile extends StatelessWidget {
  final Message msg;
  final Color fg;
  final String? url;
  const _FileTile({required this.msg, required this.fg, required this.url});
  @override
  Widget build(BuildContext context) {
    final video = (msg.mediaType ?? '').startsWith('video/');
    return InkWell(
      borderRadius: BorderRadius.circular(TRRadius.lg),
      onTap: url == null ? null : () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: fg.withValues(alpha: .1), borderRadius: BorderRadius.circular(TRRadius.lg)),
        child: Row(children: [
          Icon(video ? Icons.movie_outlined : Icons.insert_drive_file_outlined, color: fg, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(msg.mediaName ?? 'File', maxLines: 1, overflow: TextOverflow.ellipsis, style: TRText.body(13, fg, w: FontWeight.w600)),
              Text(url == null ? 'Not available' : '${fmtSize(msg.mediaSize)} · tap to open',
                  style: TRText.body(11, fg.withValues(alpha: .7))),
            ]),
          ),
          Icon(Icons.download_rounded, color: fg.withValues(alpha: .8), size: 20),
        ]),
      ),
    );
  }
}

void openImageViewer(BuildContext context, String url, String? name) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black87,
    pageBuilder: (ctx, _, __) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(name ?? '', style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
        ],
      ),
      body: GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(url))),
      ),
    ),
  ));
}
