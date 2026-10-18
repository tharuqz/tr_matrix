import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chat_appearance.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/pill_picker.dart';

class _Lbl2 extends StatelessWidget {
  final String t;
  const _Lbl2(this.t);
  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: TRText.body(11, c.tr.text3, w: FontWeight.w700)),
      );
}

Color? _try2(String s) {
  try {
    if (s == 'auto') return null;
    return Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return null;
  }
}

class ComposerTab extends StatelessWidget {
  final ChatAppearance ap;
  final ValueChanged<Map<String, dynamic>> onPatch;
  const ComposerTab({super.key, required this.ap, required this.onPatch});
  @override
  Widget build(BuildContext context) {
    final sw = [...TRAccent.swatches];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Lbl2('Composer color'),
        CircleSwatchPicker(
          colors: sw,
          value: ap.composerColor == 'auto' ? null : _try2(ap.composerColor),
          onChanged: (col) => onPatch({
            'composerColor': col == null
                ? 'auto'
                : '#${col.value.toRadixString(16).substring(2)}',
          }),
        ),
        const SizedBox(height: 10),
        const _Lbl2('Strength'),
        Slider(
          value: ap.composerVisibility.toDouble(),
          min: 35,
          max: 100,
          divisions: 13,
          activeColor: context.accent,
          onChanged: (v) => onPatch({'composerVisibility': v.round()}),
        ),
        const SizedBox(height: 10),
        const _Lbl2('Shape'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [('pill', 'Pill'), ('soft', 'Soft')])
              PillChip(
                label: e.$2,
                selected: ap.composerShape == e.$1,
                onTap: () => onPatch({'composerShape': e.$1}),
              ),
          ],
        ),
        SwitchListTile(
          value: ap.composerOutline,
          title: Text('Outline', style: TRText.body(13, context.tr.text1)),
          onChanged: (v) => onPatch({'composerOutline': v}),
        ),
      ],
    );
  }
}

class PatternTab extends StatelessWidget {
  final ChatAppearance ap;
  final ValueChanged<Map<String, dynamic>> onPatch;
  const PatternTab({super.key, required this.ap, required this.onPatch});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Lbl2('Overlay effect'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              ('none', 'None'),
              ('flow', 'Flow'),
              ('contour', 'Contour'),
              ('arcade', 'Arcade'),
            ])
              PillChip(
                label: e.$2,
                selected: ap.effect == e.$1,
                onTap: () => onPatch({'effect': e.$1}),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const _Lbl2('Effect color'),
        CircleSwatchPicker(
          colors: [...TRAccent.swatches],
          value: ap.effectColor == 'auto' ? null : _try2(ap.effectColor),
          onChanged: (col) => onPatch({
            'effectColor': col == null
                ? 'auto'
                : '#${col.value.toRadixString(16).substring(2)}',
          }),
        ),
        const SizedBox(height: 10),
        const _Lbl2('Visibility'),
        Slider(
          value: ap.effectVisibility.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          activeColor: context.accent,
          onChanged: (v) => onPatch({'effectVisibility': v.round()}),
        ),
        const _Lbl2('Scale'),
        Slider(
          value: ap.effectScale.toDouble(),
          min: 60,
          max: 180,
          divisions: 12,
          activeColor: context.accent,
          onChanged: (v) => onPatch({'effectScale': v.round()}),
        ),
        SwitchListTile(
          value: ap.effectMotion,
          title: Text('Animate', style: TRText.body(13, context.tr.text1)),
          onChanged: (v) => onPatch({'effectMotion': v}),
        ),
      ],
    );
  }
}
