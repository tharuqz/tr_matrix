import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of `avatar-crop-dialog.tsx` — zoom + drag circular crop, exports 512x512 JPEG.
class AvatarCropDialog extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  final Future<void> Function(Uint8List croppedJpeg) onConfirm;
  final VoidCallback onCancel;
  const AvatarCropDialog({
    super.key,
    required this.bytes,
    required this.name,
    required this.onConfirm,
    required this.onCancel,
  });
  static Future<void> show(
    BuildContext c,
    Uint8List bytes,
    String name,
    Future<void> Function(Uint8List) onConfirm,
  ) =>
      showDialog(
        context: c,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: AvatarCropDialog(
            bytes: bytes,
            name: name,
            onConfirm: onConfirm,
            onCancel: () => Navigator.pop(c),
          ),
        ),
      );
  @override
  State<AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<AvatarCropDialog> {
  img.Image? _decoded;
  double _zoom = 1.0;
  Offset _pos = Offset.zero;
  bool _busy = false;
  Offset? _dragStart;
  Offset? _posAtDragStart;

  @override
  void initState() {
    super.initState();
    _decoded = img.decodeImage(widget.bytes);
  }

  Future<void> _confirm() async {
    final src = _decoded;
    if (src == null) return;
    setState(() => _busy = true);
    try {
      // Simple center crop at current zoom/pan: render to 512 canvas
      const out = 512;
      final scale = (out / src.width) < (out / src.height)
          ? out / src.width
          : out / src.height;
      final effScale = scale * _zoom;
      final w = (src.width * effScale).round(),
          h = (src.height * effScale).round();
      final resized = img.copyResize(src, width: w, height: h);
      final canvas = img.Image(width: out, height: out, numChannels: 3);
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
      final dx = (out - w) ~/ 2 + _pos.dx.round();
      final dy = (out - h) ~/ 2 + _pos.dy.round();
      img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
      // circular mask
      for (var y = 0; y < out; y++) {
        for (var x = 0; x < out; x++) {
          final ddx = x - out / 2, ddy = y - out / 2;
          if (ddx * ddx + ddy * ddy > (out / 2) * (out / 2))
            canvas.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        }
      }
      final jpeg = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
      await widget.onConfirm(jpeg);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B0D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Crop your photo',
                style: TRText.body(16, Colors.white, w: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, color: c.text2),
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onPanStart: (d) {
              _dragStart = d.globalPosition;
              _posAtDragStart = _pos;
            },
            onPanUpdate: (d) {
              if (_dragStart == null || _posAtDragStart == null) return;
              setState(
                () =>
                    _pos = _posAtDragStart! + (d.globalPosition - _dragStart!),
              );
            },
            onPanEnd: (_) {
              _dragStart = null;
              _posAtDragStart = null;
            },
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_decoded != null)
                    Transform.translate(
                      offset: _pos,
                      child: Transform.scale(
                        scale: _zoom,
                        child: Image.memory(
                          widget.bytes,
                          width: 280,
                          height: 280,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF34D399).withValues(alpha: .7),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(alpha: .45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.zoom_out_rounded, color: c.text2, size: 18),
              Expanded(
                child: Slider(
                  value: _zoom,
                  min: 1,
                  max: 4,
                  divisions: 30,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (v) => setState(() => _zoom = v),
                ),
              ),
              Icon(Icons.zoom_in_rounded, color: c.text2, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Use photo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
