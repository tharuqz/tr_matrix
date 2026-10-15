import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Video;
import '../../core/theme/tokens.dart';
import 'zone_controller.dart';

/// In-app YouTube player for Windows/Linux.
/// Looks up the real video stream with youtube_explode, plays it with media_kit
/// (libmpv), and keeps it in step with the Zone's shared timeline.
class DesktopSyncedPlayer extends StatefulWidget {
  final ZoneController z;
  final String videoId;
  const DesktopSyncedPlayer({super.key, required this.z, required this.videoId});
  @override
  State<DesktopSyncedPlayer> createState() => _DesktopSyncedPlayerState();
}

class _DesktopSyncedPlayerState extends State<DesktopSyncedPlayer> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _yt = YoutubeExplode();
  Timer? _sync;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<Uri> _resolve() async {
    final m = await _yt.videos.streamsClient.getManifest(widget.videoId,
        ytClients: [YoutubeApiClient.androidVr, YoutubeApiClient.ios]);
    // Muxed = video+audio in one file (up to 360p/720p) — simplest and most reliable.
    if (m.muxed.isNotEmpty) return m.muxed.withHighestBitrate().url;
    // Fallback: audio only (still fine for "music" mode).
    return m.audioOnly.withHighestBitrate().url;
  }

  Future<void> _open() async {
    try {
      Uri url;
      try {
        url = await _resolve();
      } catch (_) {
        // Fallback: let libmpv resolve it itself (needs yt-dlp installed on the PC).
        url = Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}');
      }
      await _player.open(Media(url.toString()), play: false);
      await _player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() => _ready = true);
      await _check();
      _sync = Timer.periodic(const Duration(seconds: 4), (_) => _check());
      widget.z.addListener(_check);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play this video in the app.');
    }
  }

  Future<void> _check() async {
    if (!_ready) return;
    final playing = widget.z.zone?['is_playing'] == true;
    try {
      if (!playing) {
        if (_player.state.playing) await _player.pause();
        return;
      }
      final want = widget.z.musicPosition;
      final cur = _player.state.position.inMilliseconds / 1000;
      if ((cur - want).abs() > 2.5) {
        await _player.seek(Duration(milliseconds: (want * 1000).round()));
      }
      if (!_player.state.playing) await _player.play();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sync?.cancel();
    widget.z.removeListener(_check);
    _player.dispose();
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TRRadius.x2l),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _error != null
            ? Container(color: Colors.black, alignment: Alignment.center, child: Text(_error!, style: const TextStyle(color: Colors.white70)))
            : Stack(fit: StackFit.expand, children: [
                Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
                if (!_ready) const Center(child: CircularProgressIndicator()),
              ]),
      ),
    );
  }
}
