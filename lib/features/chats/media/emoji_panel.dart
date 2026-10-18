import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/animated_emoji.dart';
import '../../../core/emoji_picker_data.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import 'stickers.dart';

/// Panel above the message box: animated emoji picker + stickers.
class EmojiStickerPanel extends StatefulWidget {
  final String uid;
  final TextEditingController controller;
  final void Function(LocalSticker) onSticker;
  const EmojiStickerPanel({
    super.key,
    required this.uid,
    required this.controller,
    required this.onSticker,
  });
  @override
  State<EmojiStickerPanel> createState() => _EmojiStickerPanelState();
}

class _EmojiStickerPanelState extends State<EmojiStickerPanel> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    Widget tab(int i, IconData ic, String label) => InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() => _tab = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _tab == i ? context.accent.withValues(alpha: .16) : null,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, size: 16, color: _tab == i ? context.accent : c.text3),
              const SizedBox(width: 6),
              Text(label,
                  style: TRText.body(12, _tab == i ? context.accent : c.text2,
                      w: FontWeight.w600)),
            ]),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
        child: Row(children: [
          tab(0, Icons.emoji_emotions_outlined, 'Emoji'),
          const SizedBox(width: 6),
          tab(1, Icons.sticky_note_2_outlined, 'Stickers'),
        ]),
      ),
      if (_tab == 0)
        EmojiPicker(onPick: _insert)
      else
        StickerPicker(uid: widget.uid, onPick: widget.onSticker),
    ]);
  }

  void _insert(String e) {
    final t = widget.controller;
    final sel = t.selection;
    final text = t.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    t.value = TextEditingValue(
      text: text.replaceRange(start, end, e),
      selection: TextSelection.collapsed(offset: start + e.length),
    );
  }
}

class EmojiPicker extends StatefulWidget {
  final ValueChanged<String> onPick;
  const EmojiPicker({super.key, required this.onPick});
  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  static const _kRecent = 'tr.emoji.recent';
  List<String> _recent = [];
  int _cat = 1; // 0 = recent
  String _q = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final r = p.getStringList(_kRecent) ?? [];
      if (mounted) setState(() {
        _recent = r;
        if (r.isNotEmpty) _cat = 0;
      });
    });
  }

  Future<void> _pick(String e) async {
    widget.onPick(e);
    final next = [e, ..._recent.where((x) => x != e)].take(32).toList();
    setState(() => _recent = next);
    (await SharedPreferences.getInstance()).setStringList(_kRecent, next);
  }

  List<String> get _list {
    if (_q.isNotEmpty) {
      return [
        for (final cat in kEmojiPickerCategories)
          for (final e in cat.$3)
            if (e.$2.contains(_q)) e.$1
      ];
    }
    if (_cat == 0) return _recent;
    return [for (final e in kEmojiPickerCategories[_cat - 1].$3) e.$1];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final items = _list;
    return SizedBox(
      height: 300,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            style: TRText.body(13, c.text1),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search emoji',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: c.surface2,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _catBtn(0, null, Icons.history_rounded),
              for (var i = 0; i < kEmojiPickerCategories.length; i++)
                _catBtn(i + 1, kEmojiPickerCategories[i].$2, null),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(_q.isEmpty ? 'No recent emoji yet' : 'No emoji found',
                      style: TRText.body(12, c.text3)))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 46, mainAxisSpacing: 2, crossAxisSpacing: 2),
                  itemCount: items.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _pick(items[i]),
                    child: Center(
                      child: RepaintBoundary(
                          child: AnimatedEmoji(items[i], size: 32)),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _catBtn(int i, String? emoji, IconData? icon) {
    final c = context.tr;
    final on = _q.isEmpty && _cat == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _cat = i),
        child: Container(
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? context.accent.withValues(alpha: .16) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: icon != null
              ? Icon(icon, size: 18, color: on ? context.accent : c.text3)
              : Text(emoji!, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}
