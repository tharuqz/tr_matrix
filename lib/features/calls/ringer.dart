import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ringtone (incoming), ringback tone (outgoing) and phone vibration.
class Ringer {
  final AudioPlayer _player = AudioPlayer(playerId: 'tr-ringer');
  Timer? _buzz;

  bool get _phone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> startIncoming() async {
    await stop();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/ringtone.wav'), volume: 1);
    } catch (e) {
      debugPrint(
        '[ringer] $e',
      ); // browsers may block sound until the page was clicked once
    }
    if (_phone) {
      HapticFeedback.heavyImpact();
      _buzz = Timer.periodic(
        const Duration(milliseconds: 1400),
        (_) => HapticFeedback.heavyImpact(),
      );
    }
  }

  Future<void> startOutgoing() async {
    await stop();
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/ringback.wav'), volume: .6);
    } catch (e) {
      debugPrint('[ringer] $e');
    }
  }

  Future<void> stop() async {
    _buzz?.cancel();
    _buzz = null;
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
    _buzz?.cancel();
    _player.dispose();
  }
}
