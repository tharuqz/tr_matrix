import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Reusable pill / circle-swatch picker primitives matching the site's
/// circle-swatch + glow + pill-chip style. Every choice becomes a tap
/// target that glows when selected — no grey box grids.

class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected && icon != null) ...[
            Icon(icon, size: 14, color: TRAccent.on(context.accent)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TRText.body(
              13,
              selected ? TRAccent.on(context.accent) : context.tr.text1,
            ),
          ),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: context.tr.surface2,
      selectedColor: context.accent,
      side: selected
          ? BorderSide(color: context.accent.withValues(alpha: .5))
          : BorderSide.none,
      shape: const StadiumBorder(),
    );
  }
}

class CircleSwatchPicker extends StatelessWidget {
  final List<Color> colors;
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final bool allowAuto;
  const CircleSwatchPicker({
    super.key,
    required this.colors,
    required this.value,
    required this.onChanged,
    this.allowAuto = true,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (allowAuto)
          ChoiceChip(
            label: Text(
              'Auto',
              style: TRText.body(
                12,
                value == null ? TRAccent.on(context.accent) : c.text1,
              ),
            ),
            selected: value == null,
            onSelected: (_) => onChanged(null),
            backgroundColor: c.surface2,
            selectedColor: context.accent,
            side: BorderSide(color: c.border),
            shape: const StadiumBorder(),
          ),
        for (final col in colors)
          GestureDetector(
            onTap: () => onChanged(col),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == col ? context.accent : c.border,
                  width: value == col ? 2 : 1,
                ),
                boxShadow: value == col
                    ? [
                        BoxShadow(
                          color: context.accent.withValues(alpha: .5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class FontGrid extends StatelessWidget {
  final List<String> fonts;
  final String value;
  final ValueChanged<String> onChanged;
  final String Function(String label, String font) renderLabel;
  const FontGrid({
    super.key,
    required this.fonts,
    required this.value,
    required this.onChanged,
    required this.renderLabel,
  });
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 2.6,
      children: [
        for (final f in fonts)
          ChoiceChip(
            label: Text(
              renderLabel(f, f),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TRText.body(
                12,
                value == f ? TRAccent.on(context.accent) : context.tr.text1,
              ),
            ),
            selected: value == f,
            onSelected: (_) => onChanged(f),
            backgroundColor: context.tr.surface2,
            selectedColor: context.accent,
            side: BorderSide.none,
            shape: const StadiumBorder(),
          ),
      ],
    );
  }
}
