import 'package:flutter/material.dart';
import '../core/fancy.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Port of src/components/chat/text-style-picker.tsx
class TextStylePicker extends StatelessWidget {
  final TextStyleSpec value;
  final ValueChanged<TextStyleSpec> onChanged;
  final String sample;
  final bool enabled;
  const TextStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.sample,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    // A dialog with its own state so every tap updates instantly
    // (disabled popup items used to swallow all taps).
    return IconButton(
      tooltip: 'Text style',
      onPressed: !enabled
          ? null
          : () {
              var local = value;
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: c.surface1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: StatefulBuilder(
                      builder: (ctx, setLocal) {
                        final pv = encodeFancy(
                          applyFont(
                            sample.trim().isEmpty ? 'TR MATRIX' : sample.trim(),
                            local.font,
                          ),
                          local.fx,
                          local.color,
                        );
                        return _PickerSheet(
                          preview: pv,
                          value: local,
                          onChanged: (v) {
                            setLocal(() => local = v);
                            onChanged(v);
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
            },
      icon: Icon(
        Icons.text_fields_rounded,
        size: 20,
        color: value.isStyled ? context.accent : c.text2,
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  final String preview;
  final TextStyleSpec value;
  final ValueChanged<TextStyleSpec> onChanged;
  const _PickerSheet({
    required this.preview,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final colors = [...TRAccent.swatches, c.text1];
    Widget fxChip(String label, String? fx) {
      final on = value.fx == fx;
      // Glow/gradient preview for active fx chips (web parity: soft glow).
      return ActionChip(
        label: Text(
          label,
          style: TRText.body(13, on ? TRAccent.on(context.accent) : c.text1),
        ),
        backgroundColor: on ? context.accent : c.surface2,
        side: on
            ? BorderSide(color: context.accent.withValues(alpha: .5))
            : BorderSide.none,
        shape: const StadiumBorder(),
        avatar: on && fx != null
            ? Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: TRAccent.on(context.accent),
              )
            : null,
        onPressed: () => onChanged(
          fx == null ? value.copyWith(clearFx: true) : value.copyWith(fx: fx),
        ),
      );
    }

    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: FancyText(
              preview,
              style: TRText.body(16, c.text1, w: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Text('Effect', style: TRText.body(11, c.text3, w: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              fxChip('None', null),
              for (final fx in motionFx) fxChip(motionLabels[fx]!, fx),
            ],
          ),
          const SizedBox(height: 12),
          Text('Color', style: TRText.body(11, c.text3, w: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                label: Text(
                  'Auto',
                  style: TRText.body(
                    12,
                    value.color == null ? TRAccent.on(context.accent) : c.text1,
                  ),
                ),
                backgroundColor:
                    value.color == null ? context.accent : c.surface2,
                side: BorderSide(color: c.border),
                shape: const StadiumBorder(),
                onPressed: () => onChanged(value.copyWith(clearColor: true)),
              ),
              for (final col in colors)
                GestureDetector(
                  onTap: () => onChanged(value.copyWith(color: col)),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: value.color == col ? context.accent : c.border,
                        width: value.color == col ? 2 : 1,
                      ),
                      boxShadow: value.color == col
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
          ),
          const SizedBox(height: 12),
          Text('Font', style: TRText.body(11, c.text3, w: FontWeight.w600)),
          const SizedBox(height: 6),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.6,
            children: [
              for (final f in fancyFonts)
                ActionChip(
                  label: Text(
                    applyFont(fontLabels[f]!, f),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TRText.body(
                      12,
                      value.font == f ? TRAccent.on(context.accent) : c.text1,
                    ),
                  ),
                  backgroundColor:
                      value.font == f ? context.accent : c.surface2,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  onPressed: () => onChanged(value.copyWith(font: f)),
                ),
            ],
          ),
          if (value.isStyled) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => onChanged(plainStyle),
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  side: BorderSide(color: c.border),
                ),
                child: Text('Reset style', style: TRText.body(13, c.text1)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
