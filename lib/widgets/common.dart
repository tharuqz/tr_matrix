import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import '../core/motion.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';

/// Hover-aware wrapper: gives web-like hover background + pointer cursor.
class Hoverable extends StatefulWidget {
  final Widget Function(BuildContext, bool hovered) builder;
  final VoidCallback? onTap;
  final String? tooltip;
  const Hoverable({super.key, required this.builder, this.onTap, this.tooltip});
  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _h = false, _focused = false, _pressed = false;
  @override
  Widget build(BuildContext context) {
    Widget w = MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: FocusableActionDetector(
        enabled: widget.onTap != null,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: Semantics(
          button: widget.onTap != null,
          label: widget.tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown:
                widget.onTap == null
                    ? null
                    : (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? .97 : 1,
              duration: matrixDuration(context, 110),
              child: widget.builder(context, _h || _focused),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

/// "Liquid glass" panel: blurred translucent surface, 30px radius, hairline border.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = TRRadius.glass,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: c.surface1.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Shared full-bleed neutral canvas.
class MatrixBackground extends StatelessWidget {
  final Widget child;
  const MatrixBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.tr.bg, child: child);
}

class TRAvatar extends StatefulWidget {
  final String name;
  final String? url;
  final double size;
  final bool online;
  const TRAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 44,
    this.online = false,
  });

  @override
  State<TRAvatar> createState() => _TRAvatarState();
}

class _TRAvatarState extends State<TRAvatar> {
  late Future<String?> _url;
  @override
  void initState() {
    super.initState();
    _url = resolveAvatarUrl(widget.url);
  }

  @override
  void didUpdateWidget(TRAvatar old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _url = resolveAvatarUrl(widget.url);
  }

  String get _initials {
    final parts =
        widget.name
            .trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList();
    if (parts.isEmpty) return '?';
    return (parts.length == 1 ? parts.first[0] : parts[0][0] + parts[1][0])
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr, size = widget.size;
    final fallback = Text(
      _initials,
      style: TRText.display(size * .33, context.accent, w: FontWeight.w600),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.accent.withValues(alpha: .10),
            ),
            child: FutureBuilder<String?>(
              future: _url,
              builder: (_, snapshot) {
                final url = snapshot.data;
                if (url == null) return fallback;
                return Image.network(
                  url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                );
              },
            ),
          ),
          if (widget.online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * .25,
                height: size * .25,
                decoration: BoxDecoration(
                  color: c.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum TRButtonVariant { primary, ghost, outline, danger }

class TRButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TRButtonVariant variant;
  final bool loading;
  final bool large; // bigger on touch screens
  const TRButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = TRButtonVariant.primary,
    this.loading = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tr, a = context.accent;
    final disabled = onPressed == null || loading;
    return Hoverable(
      onTap: disabled ? null : onPressed,
      builder: (_, h) {
        late Color bg, fg;
        Border? border;
        switch (variant) {
          case TRButtonVariant.primary:
            bg = h ? (Color.lerp(a, c.text1, .1) ?? a) : a;
            fg = TRAccent.on(a);
          case TRButtonVariant.ghost:
            bg = h ? c.text1.withValues(alpha: .06) : Colors.transparent;
            fg = c.text1;
          case TRButtonVariant.outline:
            bg = h ? c.text1.withValues(alpha: .05) : Colors.transparent;
            fg = c.text1;
            border = Border.all(color: c.border);
          case TRButtonVariant.danger:
            bg = h ? (Color.lerp(c.danger, c.text1, .1) ?? c.danger) : c.danger;
            fg = TRAccent.on(c.danger);
        }
        return AnimatedContainer(
          duration: matrixDuration(context, 150),
          height: large ? 52 : 40,
          padding: EdgeInsets.symmetric(horizontal: large ? 22 : 16),
          decoration: BoxDecoration(
            color: disabled ? bg.withValues(alpha: .5) : bg,
            borderRadius: BorderRadius.circular(TRRadius.pill),
            border: border,
            boxShadow:
                variant == TRButtonVariant.primary && h
                    ? TRShadow.glow(a)
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else if (icon != null)
                Icon(icon, size: 18, color: fg),
              if (icon != null || loading) const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TRText.body(large ? 16 : 14, fg, w: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TRIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool active;
  const TRIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 40,
    this.active = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Hoverable(
      tooltip: tooltip,
      onTap: onPressed,
      builder:
          (_, h) => AnimatedContainer(
            duration: matrixDuration(context, 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  active
                      ? context.accent.withValues(alpha: .16)
                      : (h
                          ? c.text1.withValues(alpha: .07)
                          : Colors.transparent),
            ),
            child: Icon(
              icon,
              size: size * .5,
              color: active ? context.accent : (h ? c.text1 : c.text2),
            ),
          ),
    );
  }
}

class TRTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboard;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final int? maxLength;
  const TRTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.keyboard,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.maxLength,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TRRadius.pill),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboard,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      maxLength: maxLength,
      style: TRText.body(15, c.text1),
      cursorColor: context.accent,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: TRText.body(15, c.text3),
        prefixIcon: icon == null ? null : Icon(icon, size: 18, color: c.text3),
        filled: true,
        fillColor: c.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: border,
        border: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: context.accent, width: 1.5),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: Icon(icon, size: 30, color: context.accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TRText.display(18, c.text1, w: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TRText.body(14, c.text2),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void showToast(BuildContext context, String msg, {bool error = false}) {
  final c = context.tr;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TRRadius.xl),
        side: BorderSide(color: c.border),
      ),
      content: Text(
        msg,
        style: TRText.body(14, error ? c.danger : c.text1, w: FontWeight.w500),
      ),
    ),
  );
}

final Map<String, (String, DateTime)> _avatarCache = {};

/// Website stores avatars as private storage paths ("<uid>/avatar-123.png"); turn them into viewable links.
Future<String?> resolveAvatarUrl(String? path) async {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return path;
  final hit = _avatarCache[path];
  if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
  try {
    final u = await Supabase.instance.client.storage
        .from('avatars')
        .createSignedUrl(path, 3600);
    _avatarCache[path] = (u, DateTime.now().add(const Duration(minutes: 55)));
    return u;
  } catch (_) {
    return null;
  }
}

class MatrixTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const MatrixTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: labels.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder:
          (_, i) => Hoverable(
            onTap: () => onChanged(i),
            builder:
                (_, hovered) => AnimatedContainer(
                  duration: matrixDuration(context, 180),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color:
                        selected == i
                            ? context.accent.withValues(alpha: .14)
                            : (hovered
                                ? context.tr.surface2
                                : Colors.transparent),
                    borderRadius: BorderRadius.circular(TRRadius.pill),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    style: TRText.body(
                      13,
                      selected == i ? context.accent : context.tr.text2,
                      w: FontWeight.w600,
                    ),
                  ),
                ),
          ),
    ),
  );
}
