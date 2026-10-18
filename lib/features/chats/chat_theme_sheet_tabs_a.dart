import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chat_appearance.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/pill_picker.dart';

class _Lbl extends StatelessWidget {
  final String t;
  const _Lbl(this.t);
  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: TRText.body(11, c.tr.text3, w: FontWeight.w700)),
      );
}

Color? _try(String s) {
  try {
    if (s == 'auto') return null;
    return Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return null;
  }
}

class BgTab extends StatelessWidget {
  final ChatAppearance ap;
  final ValueChanged<Map<String, dynamic>> onPatch;
  const BgTab({super.key, required this.ap, required this.onPatch});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Lbl('Background'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              ('original', 'Original'),
              ('solid', 'Solid'),
              ('preset', 'Preset'),
            ])
              PillChip(
                label: e.$2,
                selected: ap.background == e.$1,
                onTap: () => onPatch({'background': e.$1}),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (ap.background == 'preset') ...[
          const _Lbl('Preset'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in [
                ('breathe', 'Breathe'),
                ('aurora', 'Aurora'),
                ('waves', 'Waves'),
              ])
                PillChip(
                  label: e.$2,
                  selected: ap.preset == e.$1,
                  onTap: () => onPatch({'preset': e.$1}),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        const _Lbl('Dim'),
        Slider(
          value: ap.dim.toDouble(),
          min: 0,
          max: 85,
          divisions: 17,
          label: '${ap.dim}%',
          activeColor: context.accent,
          onChanged: (v) => onPatch({'dim': v.round()}),
        ),
        const _Lbl('Blur'),
        Slider(
          value: ap.blur.toDouble(),
          min: 0,
          max: 12,
          divisions: 12,
          label: '${ap.blur}',
          activeColor: context.accent,
          onChanged: (v) => onPatch({'blur': v.round()}),
        ),
        const _Lbl('Fit'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              ('cover', 'Cover'),
              ('contain', 'Contain'),
              ('repeat', 'Repeat'),
            ])
              PillChip(
                label: e.$2,
                selected: ap.fit == e.$1,
                onTap: () => onPatch({'fit': e.$1}),
              ),
          ],
        ),
        SwitchListTile(
          value: ap.motion,
          title: Text('Motion', style: TRText.body(13, c.text1)),
          onChanged: (v) => onPatch({'motion': v}),
        ),
        SwitchListTile(
          value: ap.focus,
          title: Text('Focus mode', style: TRText.body(13, c.text1)),
          onChanged: (v) => onPatch({'focus': v}),
        ),
      ],
    );
  }
}

class BubblesTab extends StatelessWidget {
  final ChatAppearance ap;
  final ValueChanged<Map<String, dynamic>> onPatch;
  const BubblesTab({super.key, required this.ap, required this.onPatch});
  @override
  Widget build(BuildContext context) {
    final sw = [...TRAccent.swatches];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Lbl('Theme preset'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in chatThemes)
              PillChip(
                label: t.$2,
                selected: ap.theme == t.$1,
                onTap: () => onPatch({'theme': t.$1}),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const _Lbl('My bubble color'),
        CircleSwatchPicker(
          colors: sw,
          value: _try(ap.color),
          onChanged: (col) => onPatch({
            'color': col == null
                ? '#3b82f6'
                : '#${col.value.toRadixString(16).substring(2)}',
          }),
          allowAuto: false,
        ),
        const SizedBox(height: 12),
        const _Lbl('Shape'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in [
              ('classic', 'Classic'),
              ('soft', 'Soft'),
              ('capsule', 'Capsule'),
            ])
              PillChip(
                label: e.$2,
                selected: ap.shape == e.$1,
                onTap: () => onPatch({'shape': e.$1}),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const _Lbl('Visibility'),
        Slider(
          value: ap.visibility.toDouble(),
          min: 35,
          max: 100,
          divisions: 13,
          label: '${ap.visibility}%',
          activeColor: context.accent,
          onChanged: (v) => onPatch({'visibility': v.round()}),
        ),
        const SizedBox(height: 10),
        const _Lbl('Reply bubble'),
        CircleSwatchPicker(
          colors: sw,
          value: ap.receivedColor == 'auto' ? null : _try(ap.receivedColor),
          onChanged: (col) => onPatch({
            'receivedColor': col == null
                ? 'auto'
                : '#${col.value.toRadixString(16).substring(2)}',
          }),
        ),
        const SizedBox(height: 8),
        const _Lbl('Reply visibility'),
        Slider(
          value: ap.receivedVisibility.toDouble(),
          min: 35,
          max: 100,
          divisions: 13,
          activeColor: context.accent,
          onChanged: (v) => onPatch({'receivedVisibility': v.round()}),
        ),
      ],
    );
  }
}
