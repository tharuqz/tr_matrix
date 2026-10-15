import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/common.dart';

String fmtDur(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Recording bar that replaces the message box while recording.
/// Web (Chrome) records WebM/Opus like the website; phones/desktop record M4A.
class VoiceRecorderBar extends StatefulWidget {
  final VoidCallback onCancel;
  final void Function(String name, Uint8List bytes, String mime) onSend;
  const VoiceRecorderBar({super.key, required this.onCancel, required this.onSend});
  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _rec = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _stopping = false;

  bool get _web => kIsWeb;
  String get _ext => _web ? 'webm' : 'm4a';
  String get _mime => _web ? 'audio/webm' : 'audio/mp4';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _rec.hasPermission()) {
      if (mounted) showToast(context, 'Microphone permission is needed', error: true);
      widget.onCancel();
      return;
    }
    var path = '';
    if (!_web) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.$_ext';
    }
    await _rec.start(RecordConfig(encoder: _web ? AudioEncoder.opus : AudioEncoder.aacLc), path: path);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _finish(bool send) async {
    if (_stopping) return;
    _stopping = true;
    _timer?.cancel();
    final out = await _rec.stop();
    if (!send || out == null) return widget.onCancel();
    // On web `out` is a blob: URL; XFile reads both blob URLs and file paths.
    final bytes = await XFile(out).readAsBytes();
    widget.onSend('voice-${DateTime.now().millisecondsSinceEpoch}.$_ext', bytes, _mime);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Row(children: [
      TRIconButton(icon: Icons.delete_outline_rounded, tooltip: 'Discard', onPressed: () => _finish(false)),
      const SizedBox(width: 8),
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Icon(Icons.mic_rounded, color: c.text2, size: 18),
      const SizedBox(width: 6),
      Expanded(child: Text('Recording  ${fmtDur(_elapsed)}', style: TRText.body(14, c.text1))),
      Hoverable(
        tooltip: 'Send voice note',
        onTap: () => _finish(true),
        builder: (_, __) => Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle),
          child: Icon(Icons.send_rounded, size: 20, color: TRAccent.on(context.accent)),
        ),
      ),
    ]);
  }
}

/// Voice note bubble with play/pause and a seekable progress bar.
class VoiceNotePlayer extends StatefulWidget {
  final String url;
  final Color fg;
  const VoiceNotePlayer({super.key, required this.url, required this.fg});
  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _p = AudioPlayer();
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _p.setSourceUrl(widget.url).catchError((_) {});
    _subs.addAll([
      _p.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null),
      _p.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null),
      _p.onPlayerStateChanged.listen((s) => mounted ? setState(() => _playing = s == PlayerState.playing) : null),
      _p.onPlayerComplete.listen((_) => mounted ? setState(() => _pos = Duration.zero) : null),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final max = _dur.inMilliseconds <= 0 ? 1.0 : _dur.inMilliseconds.toDouble();
    return SizedBox(
      width: 240,
      child: Row(children: [
        IconButton(
          tooltip: _playing ? 'Pause' : 'Play',
          icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: fg, size: 34),
          onPressed: () => _playing ? _p.pause() : _p.resume(),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: fg,
                inactiveTrackColor: fg.withValues(alpha: .3),
                thumbColor: fg,
              ),
              child: Slider(
                value: _pos.inMilliseconds.clamp(0, max).toDouble(),
                max: max,
                onChanged: (v) => _p.seek(Duration(milliseconds: v.round())),
              ),
            ),
            const SizedBox(height: 4),
            Text('${fmtDur(_pos)} / ${fmtDur(_dur)}', style: TRText.body(11, fg.withValues(alpha: .75))),
          ]),
        ),
      ]),
    );
  }
}
