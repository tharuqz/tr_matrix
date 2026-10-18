import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';

/// Port of `multi-file-queue-dialog.tsx`.
///
/// Shows a preview grid for picked files, single large preview, validation
/// hints and a Send button that streams `onSendAll` with per-file results.
/// Caller is responsible for actually uploading/sending; this dialog is UI.
class MultiFileQueueDialog extends StatefulWidget {
  final List<PlatformFile> files;
  final Future<void> Function(
    List<PlatformFile> ready,
    void Function(PlatformFile, bool) onResult,
  ) onSendAll;
  final VoidCallback onCancel;
  const MultiFileQueueDialog({
    super.key,
    required this.files,
    required this.onSendAll,
    required this.onCancel,
  });
  static Future<void> show(
    BuildContext c,
    List<PlatformFile> files,
    Future<void> Function(List<PlatformFile>, void Function(PlatformFile, bool))
        onSendAll,
  ) {
    return showDialog(
      context: c,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: MultiFileQueueDialog(
          files: files,
          onSendAll: onSendAll,
          onCancel: () => Navigator.pop(c),
        ),
      ),
    );
  }

  @override
  State<MultiFileQueueDialog> createState() => _MultiFileQueueDialogState();
}

class _MultiFileQueueDialogState extends State<MultiFileQueueDialog> {
  late List<PlatformFile> _queue;
  PlatformFile? _selected;
  bool _sending = false;
  final _results = <PlatformFile, bool>{};
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _queue = List.of(widget.files);
    _selected = _queue.isNotEmpty ? _queue.first : null;
  }

  List<PlatformFile> get _ready =>
      _queue.where((f) => _results[f] != true).toList();

  Future<void> _send() async {
    if (_locked || _ready.isEmpty) return;
    _locked = true;
    setState(() => _sending = true);
    try {
      await widget.onSendAll(_ready, (file, ok) {
        if (mounted) setState(() => _results[file] = ok);
      });
    } catch (_) {}
    _locked = false;
    if (mounted) setState(() => _sending = false);
  }

  void _remove(PlatformFile f) {
    setState(() {
      _queue.remove(f);
      if (_selected == f) _selected = _queue.isNotEmpty ? _queue.first : null;
    });
  }

  bool _isMedia(PlatformFile f) => (f.name.toLowerCase().endsWith('.jpg') ||
      f.name.toLowerCase().endsWith('.png') ||
      f.name.toLowerCase().endsWith('.jpeg') ||
      f.name.toLowerCase().endsWith('.webp') ||
      f.name.toLowerCase().endsWith('.mp4') ||
      f.name.toLowerCase().endsWith('.mov'));

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_queue.length} attachments',
                  style: TRText.body(16, c.text1, w: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: c.text2),
                onPressed: _locked ? null : widget.onCancel,
              ),
            ],
          ),
          if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${_results.values.where((v) => v).length} sent · ${_ready.length} remaining',
                style: TRText.body(12, c.text2),
              ),
            ),
          if (_selected != null) ...[
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: _isMedia(_selected!)
                    ? Icon(Icons.image_rounded, size: 48, color: c.text3)
                    : Icon(
                        Icons.insert_drive_file_rounded,
                        size: 40,
                        color: c.text3,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selected!.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TRText.body(12, c.text2),
            ),
            const SizedBox(height: 10),
          ],
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _queue.length,
              itemBuilder: (_, i) {
                final f = _queue[i];
                final ok = _results[f];
                return Stack(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selected = f),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selected == f
                              ? context.accent.withValues(alpha: .18)
                              : c.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selected == f ? context.accent : c.border,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            f.name.toLowerCase().endsWith('.mp4')
                                ? Icons.movie_rounded
                                : Icons.insert_drive_file_rounded,
                            color: c.text2,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: _sending || ok == true ? null : () => _remove(f),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: c.surface3,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: c.text2,
                          ),
                        ),
                      ),
                    ),
                    if (ok == true)
                      const Positioned(
                        bottom: 4,
                        right: 4,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    if (ok == false)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: c.surface3,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.error_rounded,
                            size: 12,
                            color: c.danger,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: _sending ? null : widget.onCancel,
                child: Text(
                  _ready.isEmpty && _results.isNotEmpty ? 'Done' : 'Cancel',
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _sending || _ready.isEmpty ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Send ${_ready.length}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
