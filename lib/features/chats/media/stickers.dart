import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/common.dart';

const stickerLimit = 1024 * 1024;

class LocalSticker {
  final String id, name;
  final Uint8List bytes;
  LocalSticker(this.id, this.name, this.bytes);
  String get mime => name.endsWith('.gif') ? 'image/gif' : 'image/png';
}

/// Saved stickers live on this device only (like the website), per account.
class StickerStore {
  static String _key(String uid) => 'trmx-stickers:$uid';

  static Future<List<LocalSticker>> list(String uid) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_key(uid)) ?? []).map((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return LocalSticker(j['id'], j['name'], base64Decode(j['b64']));
    }).toList();
  }

  static Future<LocalSticker> save(String uid, Uint8List bytes, {bool gif = false}) async {
    final id = sha256.convert(bytes).toString();
    final s = LocalSticker(id, 'trmx-sticker-$id.${gif ? 'gif' : 'png'}', bytes);
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_key(uid)) ?? [])
        .where((e) => (jsonDecode(e) as Map)['id'] != id)
        .toList()
      ..insert(0, jsonEncode({'id': id, 'name': s.name, 'b64': base64Encode(bytes)}));
    await p.setStringList(_key(uid), cur);
    return s;
  }

  static Future<void> remove(String uid, String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _key(uid), (p.getStringList(_key(uid)) ?? []).where((e) => (jsonDecode(e) as Map)['id'] != id).toList());
  }

  /// Turn any picture into a 512×512 PNG sticker (GIFs are kept as-is if small enough).
  static Uint8List make(Uint8List src, String name) {
    if (src.length > 10 * 1024 * 1024) throw 'Choose an image under 10 MB.';
    if (name.toLowerCase().endsWith('.gif')) {
      if (src.length > stickerLimit) throw 'Animated GIF stickers must be under 1 MB.';
      return src;
    }
    final im = img.decodeImage(src);
    if (im == null) throw 'That picture could not be opened.';
    final scale = (512 / im.width) < (512 / im.height) ? 512 / im.width : 512 / im.height;
    final w = (im.width * scale).round(), h = (im.height * scale).round();
    final canvas = img.Image(width: 512, height: 512, numChannels: 4);
    img.compositeImage(canvas, img.copyResize(im, width: w, height: h), dstX: (512 - w) ~/ 2, dstY: (512 - h) ~/ 2);
    final out = Uint8List.fromList(img.encodePng(canvas));
    if (out.length > stickerLimit) throw 'Sticker is too detailed. Choose a simpler image.';
    return out;
  }
}

/// Sticker panel shown above the message box.
class StickerPicker extends StatefulWidget {
  final String uid;
  final void Function(LocalSticker) onPick;
  const StickerPicker({super.key, required this.uid, required this.onPick});
  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  List<LocalSticker> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await StickerStore.list(widget.uid);
    if (mounted) setState(() => _items = l);
  }

  Future<void> _create() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.firstOrNull;
    if (f?.bytes == null) return;
    setState(() => _busy = true);
    try {
      final bytes = StickerStore.make(f!.bytes!, f.name);
      await StickerStore.save(widget.uid, bytes, gif: f.name.toLowerCase().endsWith('.gif'));
      await _reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      height: 240,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: c.surface2, borderRadius: BorderRadius.circular(TRRadius.x2l), border: Border.all(color: c.border)),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 88, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemCount: _items.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Hoverable(
              tooltip: 'Make a sticker from a picture',
              onTap: _busy ? null : _create,
              builder: (_, h) => Container(
                decoration: BoxDecoration(
                    color: h ? context.accent.withValues(alpha: .15) : c.surface3,
                    borderRadius: BorderRadius.circular(TRRadius.lg)),
                child: _busy
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Icon(Icons.add_photo_alternate_outlined, color: c.text2),
              ),
            );
          }
          final s = _items[i - 1];
          return GestureDetector(
            onTap: () => widget.onPick(s),
            onLongPress: () async {
              await StickerStore.remove(widget.uid, s.id);
              _reload();
            },
            child: Tooltip(message: 'Tap to send · long-press to remove', child: Image.memory(s.bytes, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
