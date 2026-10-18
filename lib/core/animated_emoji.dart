import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'animated_emoji_codes.dart';
import 'config.dart';

/// Telegram-style animated emoji.
///
/// Only the small code list ships inside the app. Each animation (~100 KB)
/// is downloaded the first time it is shown, saved on disk, and then loads
/// instantly offline. Point the app at your hosted pack with
///   --dart-define=ANIMATED_EMOJI_BASE_URL=https://cdn.example.com/animated-emoji
class AnimatedEmojiConfig {
  static const baseUrl = String.fromEnvironment(
    'ANIMATED_EMOJI_BASE_URL',
    defaultValue: '${AppConfig.siteUrl}/animated-emoji',
  );
}

final _emojiRe = RegExp(r'\p{Extended_Pictographic}|\p{Regional_Indicator}',
    unicode: true);
final _skinTone = RegExp(r'-1f3f[b-f]');

String emojiCode(String grapheme) => grapheme.runes
    .where((r) => r != 0xFE0F)
    .map((r) => r.toRadixString(16))
    .join('-');

/// Returns the pack code for [grapheme], or null if it has no animation.
String? animatedEmojiCode(String grapheme) {
  if (!_emojiRe.hasMatch(grapheme)) return null;
  final code = emojiCode(grapheme);
  if (kAnimatedEmojiCodes.contains(code)) return code;
  final base = code.replaceAll(_skinTone, '');
  return kAnimatedEmojiCodes.contains(base) ? base : null;
}

bool isEmojiOnlyText(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  for (final g in t.characters) {
    if (g.trim().isEmpty) continue;
    if (!_emojiRe.hasMatch(g)) return false;
  }
  return true;
}

/// Disk + memory cache shared by every emoji on screen.
class AnimatedEmojiCache {
  AnimatedEmojiCache._();
  static final instance = AnimatedEmojiCache._();

  final Map<String, Future<Uint8List?>> _pending = {};
  final Map<String, Uint8List> _memory = {};
  final Set<String> _failed = {};
  Directory? _dir;

  Uint8List? peek(String code) => _memory[code];

  void _retryLater(String code) {
    _failed.add(code);
    Timer(const Duration(minutes: 1), () => _failed.remove(code));
  }

  Future<Uint8List?> load(String code) {
    final hit = _memory[code];
    if (hit != null) return SynchronousFuture(hit);
    if (_failed.contains(code)) return SynchronousFuture(null);
    return _pending[code] ??= _fetch(code).whenComplete(() => _pending.remove(code));
  }

  Future<Uint8List?> _fetch(String code) async {
    try {
      if (!kIsWeb) {
        _dir ??= Directory(
            '${(await getApplicationSupportDirectory()).path}/animated_emoji');
        final f = File('${_dir!.path}/$code.webp');
        if (await f.exists()) {
          final saved = await f.readAsBytes();
          if (saved.length > 64) return _memory[code] = saved;
          await f.delete(); // damaged file: download again
        }
        final bytes = await _download(code);
        if (bytes == null) return null;
        await _dir!.create(recursive: true);
        // Temp file + rename: a closed app never leaves a half-saved emoji.
        final tmp = File('${f.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        if (await f.exists()) await f.delete();
        await tmp.rename(f.path);
        return _memory[code] = bytes;
      }
      final bytes = await _download(code);
      if (bytes != null) _memory[code] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('[emoji] $code: $e');
      _retryLater(code); // offline: try again later, not never
      return null;
    }
  }

  Future<Uint8List?> _download(String code) async {
    final res = await http
        .get(Uri.parse('${AnimatedEmojiConfig.baseUrl}/$code.webp'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) {
      _failed.add(code);
      return null;
    }
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      _retryLater(code);
      return null;
    }
    return res.bodyBytes;
  }
}

/// One always-playing animated emoji. Shows the normal emoji while loading
/// or if the animation is unavailable.
class AnimatedEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  const AnimatedEmoji(this.emoji, {super.key, this.size = 22});

  @override
  State<AnimatedEmoji> createState() => _AnimatedEmojiState();
}

class _AnimatedEmojiState extends State<AnimatedEmoji> {
  String? _code;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AnimatedEmoji old) {
    super.didUpdateWidget(old);
    if (old.emoji != widget.emoji) _resolve();
  }

  void _resolve() {
    _code = animatedEmojiCode(widget.emoji);
    final code = _code;
    _bytes = code == null ? null : AnimatedEmojiCache.instance.peek(code);
    if (code != null && _bytes == null) {
      AnimatedEmojiCache.instance.load(code).then((b) {
        if (mounted && b != null && _code == code) setState(() => _bytes = b);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final fallback = SizedBox(
      width: s,
      height: s,
      child: Center(
        child: Text(widget.emoji,
            style: TextStyle(fontSize: s * .78, height: 1),
            textScaler: TextScaler.noScaling),
      ),
    );
    final b = _bytes;
    // Hidden from the screen-reader tree: swapping placeholder -> animation
    // inside text caused Windows "Failed to update ui::AXTree" spam.
    if (b == null) return ExcludeSemantics(child: fallback);
    return ExcludeSemantics(child: Image.memory(
      b,
      width: s,
      height: s,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      // Animated WebP decodes and loops natively on every Flutter platform.
      errorBuilder: (_, __, ___) => fallback,
      excludeFromSemantics: true,
    ));
  }
}

/// Text with every emoji animated — inline in normal sentences too, not only
/// when the message is emoji-only. Emoji-only messages are shown large.
class AnimatedEmojiText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool jumbo;
  const AnimatedEmojiText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.textAlign,
    this.jumbo = true,
  });

  static bool hasAnimated(String text) =>
      _emojiRe.hasMatch(text) &&
      text.characters.any((g) => animatedEmojiCode(g) != null);

  @override
  Widget build(BuildContext context) {
    final big = jumbo && maxLines == null && isEmojiOnlyText(text);
    final scale = MediaQuery.textScalerOf(context);
    final base = style.fontSize ?? 14;
    final size = big
        ? (text.characters.where((g) => g.trim().isNotEmpty).length <= 3 ? 72.0 : 48.0)
        : scale.scale(base) * 1.3;
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString()));
      buf.clear();
    }

    for (final g in text.characters) {
      if (animatedEmojiCode(g) != null) {
        flush();
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: RepaintBoundary(child: AnimatedEmoji(g, size: size)),
        ));
      } else {
        buf.write(g);
      }
    }
    flush();
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: big ? TextAlign.center : textAlign,
    );
  }
}
