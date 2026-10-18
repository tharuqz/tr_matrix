import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/app_scope.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import 'call_controller.dart';
import 'call_window.dart';

/// Sits above every screen: incoming-call card, full call screen, mini window.
class CallOverlay extends StatelessWidget {
  final Widget child;
  const CallOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final calls = AppScope.of(context).calls;
    return ListenableBuilder(
      listenable: calls,
      builder: (context, _) {
        if (calls.error != null) {
          final msg = calls.error!;
          calls.clearError();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final m = ScaffoldMessenger.maybeOf(context);
            m?.showSnackBar(
              SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
            );
          });
        }
        final c = calls.call;
        final desktopUi = (isDesktopNative || kIsWeb) &&
            !Responsive.isMobile(context);
        final desktopIncoming = c != null &&
            c.status == CallStatus.incoming &&
            (isDesktopNative || kIsWeb) &&
            !Responsive.isMobile(context);
        // The call layers sit ABOVE the app's Navigator, so they get their own
        // Overlay / Navigator — without it tooltips & dialogs threw the red
        // "No Overlay widget found" error and the call got stuck.
        return Stack(
          children: [
            child,
            if (c != null &&
                c.status == CallStatus.incoming &&
                !desktopIncoming)
              Positioned.fill(
                child: _OwnOverlay(
                  child: Stack(
                    children: [_Incoming(calls: calls, call: c)],
                  ),
                ),
              ),
            if (desktopIncoming)
              Positioned.fill(
                child: _OwnOverlay(
                  child: CallWindow(
                    key: const ValueKey('incoming-window'),
                    title: 'Incoming call · ${c.title}',
                    initialSize: const Size(380, 540),
                    allowExpand: false,
                    child: IncomingCallPage(calls: calls, call: c),
                  ),
                ),
              ),
            if (c != null &&
                c.status != CallStatus.incoming &&
                !calls.minimized)
              Positioned.fill(
                child: desktopUi
                    ? _OwnOverlay(
                        child: CallWindow(
                          key: const ValueKey('call-window'),
                          title: c.isGroup ? '${c.title} · hive call' : c.title,
                          onMinimize: () => calls.setMinimized(true),
                          child: _CallNavigator(calls: calls),
                        ),
                      )
                    : _CallNavigator(calls: calls),
              ),
            if (c != null && c.status != CallStatus.incoming && calls.minimized)
              Positioned.fill(
                child: _OwnOverlay(
                  child: Stack(
                    children: [_Mini(calls: calls, call: c)],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Gives a layer its own Overlay so Tooltip / InkWell work; empty areas let
/// taps fall through to the app underneath.
class _OwnOverlay extends StatefulWidget {
  final Widget child;
  const _OwnOverlay({required this.child});
  @override
  State<_OwnOverlay> createState() => _OwnOverlayState();
}

class _OwnOverlayState extends State<_OwnOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);
  @override
  void didUpdateWidget(covariant _OwnOverlay old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry.mounted) _entry.markNeedsBuild();
    });
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

/// Full call screen inside its own Navigator so the screen-share picker
/// dialog opens on top of the call (not behind it).
class _CallNavigator extends StatefulWidget {
  final CallController calls;
  const _CallNavigator({required this.calls});
  @override
  State<_CallNavigator> createState() => _CallNavigatorState();
}

class _CallNavigatorState extends State<_CallNavigator> {
  final _key = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) {
    final calls = widget.calls;
    return NavigatorPopHandler(
      onPop: () => _key.currentState?.maybePop(),
      child: Navigator(
        key: _key,
        onGenerateRoute: (_) => PageRouteBuilder(
          pageBuilder: (_, __, ___) => ListenableBuilder(
            listenable: calls,
            builder: (_, __) {
              final c = calls.call;
              if (c == null) return const SizedBox.shrink();
              return Material(
                type: MaterialType.transparency,
                child: _CallScreen(calls: calls, call: c),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Telegram / WhatsApp-style full-window incoming call page (desktop).
class IncomingCallPage extends StatefulWidget {
  final CallController calls;
  final ActiveCall call;
  const IncomingCallPage({super.key, required this.calls, required this.call});
  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _a.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _accept() {
    if (_busy) return;
    setState(() => _busy = true);
    widget.calls.accept();
  }

  void _decline() {
    if (_busy) return;
    setState(() => _busy = true);
    widget.calls.reject();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final accent = context.accent;
    final call = widget.call;
    return KeyboardListener(
      focusNode: _focus,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey == LogicalKeyboardKey.enter) _accept();
        if (e.logicalKey == LogicalKeyboardKey.escape) _decline();
      },
      child: Material(
        color: c.bg,
        child: AnimatedBuilder(
          animation: _a,
          builder: (context, _) {
            final t = _a.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + t * .6, -1),
                  end: Alignment(1, 1 - t * .6),
                  colors: [
                    accent.withValues(alpha: .35),
                    c.bg,
                    c.success.withValues(alpha: .18),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, size: 13, color: c.text2),
                        const SizedBox(width: 6),
                        Text(
                          'TR MATRIX  ·  end-to-end call',
                          style: TRText.body(12, c.text2),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Builder(
                              builder: (_) {
                                final p = (t + i / 3) % 1;
                                return Container(
                                  width: 130 + p * 130,
                                  height: 130 + p * 130,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: accent.withValues(
                                        alpha: (1 - p) * .55,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                );
                              },
                            ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(
                                    alpha: .45 + .25 * (1 - (t * 2 - 1).abs()),
                                  ),
                                  blurRadius: 40,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: TRAvatar(
                              name: call.title,
                              url: call.avatar,
                              size: 120,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      call.title,
                      style: TRText.display(30, c.text1),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          call.isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          size: 16,
                          color: c.text2,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _statusText(widget.calls, call),
                          style: TRText.body(15, c.text2),
                        ),
                        for (var i = 0; i < 3; i++)
                          Opacity(
                            opacity: ((t * 3 - i) % 3) < 1 ? 1 : .25,
                            child: Text(
                              '.',
                              style: TRText.body(
                                15,
                                c.text2,
                                w: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _bigButton(
                          c.danger,
                          Icons.call_end_rounded,
                          'Decline',
                          _decline,
                          t,
                          false,
                        ),
                        const SizedBox(width: 72),
                        _bigButton(
                          c.success,
                          call.isVideo
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          'Accept',
                          _accept,
                          t,
                          true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Enter to answer  ·  Esc to decline',
                      style: TRText.body(11, c.text2.withValues(alpha: .7)),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bigButton(
    Color color,
    IconData icon,
    String label,
    VoidCallback onTap,
    double t,
    bool wiggle,
  ) {
    final c = context.tr;
    final angle = wiggle && t < .25 ? sin(t * 4 * pi * 4) * .18 : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .5),
                blurRadius: 24 + 10 * sin(t * 2 * pi).abs(),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _busy ? null : onTap,
              child: SizedBox(
                width: 76,
                height: 76,
                child: Transform.rotate(
                  angle: angle,
                  child: Icon(icon, color: Colors.white, size: 34),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: TRText.body(13, c.text1, w: FontWeight.w600)),
      ],
    );
  }
}

String _statusText(CallController calls, ActiveCall c) {
  switch (c.status) {
    case CallStatus.incoming:
      return c.isGroup
          ? '${calls.groupInviter} is calling the group'
          : 'Incoming ${c.isVideo ? 'video' : 'voice'} call';
    case CallStatus.outgoing:
      return 'Ringing…';
    case CallStatus.connecting:
      return 'Connecting…';
    case CallStatus.active:
      return '';
  }
}

class _Timer extends StatefulWidget {
  final DateTime? since;
  final TextStyle style;
  const _Timer(this.since, this.style);
  @override
  State<_Timer> createState() => _TimerState();
}

class _TimerState extends State<_Timer> {
  late final Timer _t = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.since == null
        ? 0
        : DateTime.now().difference(widget.since!).inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0'),
        ss = (s % 60).toString().padLeft(2, '0');
    return Text('$mm:$ss', style: widget.style);
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;
  final double size;
  const _Round({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.active = false,
    this.size = 56,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final bg = color ?? (active ? c.text1 : c.text1.withValues(alpha: .12));
    final fg = color != null ? Colors.white : (active ? c.bg : c.text1);
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: fg, size: size * .42),
            ),
          ),
        ),
      ),
    );
  }
}

class _Incoming extends StatelessWidget {
  final CallController calls;
  final ActiveCall call;
  const _Incoming({required this.calls, required this.call});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final mobile = Responsive.isMobile(context);
    final card = Container(
      width: mobile ? double.infinity : 360,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(TRRadius.glass),
        border: Border.all(color: c.border),
        boxShadow: TRShadow.md(Colors.black),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TRAvatar(name: call.title, url: call.avatar, size: 72),
          const SizedBox(height: 12),
          Text(
            call.title,
            style: TRText.display(20, c.text1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(_statusText(calls, call), style: TRText.body(13, c.text2)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Round(
                icon: Icons.call_end_rounded,
                label: 'Decline',
                color: c.danger,
                onTap: calls.reject,
                size: 60,
              ),
              const SizedBox(width: 28),
              _Round(
                icon:
                    call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                label: 'Accept',
                color: c.success,
                onTap: calls.accept,
                size: 60,
              ),
            ],
          ),
        ],
      ),
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 16,
      left: mobile ? 16 : null,
      right: 16,
      child: Material(type: MaterialType.transparency, child: card),
    );
  }
}

class _Tile extends StatelessWidget {
  final RTCVideoRenderer? renderer;
  final bool showVideo, mirror;
  final String name;
  final String? avatar;
  final bool contain;
  const _Tile({
    this.renderer,
    required this.showVideo,
    required this.name,
    this.avatar,
    this.mirror = false,
    this.contain = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final hasTexture = renderer != null && renderer!.textureId != null;
    final canShowVideo = showVideo && hasTexture;
    if (canShowVideo) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(TRRadius.x2l),
          child: Container(
            color: c.surface1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RTCVideoView(
                  renderer!,
                  mirror: mirror,
                  objectFit: contain
                      ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                      : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(TRRadius.pill),
                    ),
                    child: Text(
                      name,
                      style: TRText.body(12, Colors.white, w: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } catch (_) {}
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(TRRadius.x2l),
      child: Container(
        color: c.surface1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: TRAvatar(name: name, url: avatar, size: 84),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(TRRadius.pill),
                ),
                child: Text(
                  name,
                  style: TRText.body(12, Colors.white, w: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallScreen extends StatelessWidget {
  final CallController calls;
  final ActiveCall call;
  const _CallScreen({required this.calls, required this.call});

  Future<void> _share(BuildContext context) async {
    if (calls.sharing) return calls.stopScreenShare();
    if (isDesktopNative) {
      final id = await showDialog<String>(
        context: context,
        builder: (_) => const _ScreenPicker(),
      );
      if (id != null) await calls.startScreenShare(desktopSourceId: id);
    } else {
      await calls.startScreenShare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final me = AppScope.of(context).auth.profile;
    final peers = calls.peerList.where((p) => p.pc != null).toList();
    final status = _statusText(calls, call);
    final localTile = _Tile(
      renderer: calls.localRenderer,
      showVideo: (call.isVideo && !calls.cameraOff) || calls.sharing,
      name: calls.sharing ? 'You (sharing)' : 'You',
      avatar: me?.avatarUrl,
      mirror: !calls.sharing,
      contain: calls.sharing,
    );

    Widget stage;
    if (peers.isEmpty) {
      stage = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TRAvatar(name: call.title, url: call.avatar, size: 110),
            const SizedBox(height: 16),
            Text(call.title, style: TRText.display(24, c.text1)),
            const SizedBox(height: 6),
            Text(status, style: TRText.body(14, c.text2)),
          ],
        ),
      );
    } else {
      final cols = peers.length <= 1 ? 1 : (peers.length <= 4 ? 2 : 3);
      stage = GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: Responsive.isMobile(context) && peers.length > 1
            ? 1 + (peers.length > 2 ? 1 : 0)
            : cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: peers.length == 1
            ? MediaQuery.sizeOf(context).aspectRatio.clamp(.5, 2.0)
            : 16 / 10,
        children: [
          for (final p in peers)
            _Tile(
              renderer: p.renderer,
              showVideo: p.hasVideo,
              name: p.name,
              avatar: p.avatar,
              contain: true,
            ),
        ],
      );
    }

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: stage),
            // Header
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  TRIconButton(
                    icon: Icons.close_fullscreen_rounded,
                    tooltip: 'Minimize',
                    onPressed: () => calls.setMinimized(true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          call.isGroup
                              ? '${call.title} · ${peers.length + 1} people'
                              : call.title,
                          style: TRText.body(15, c.text1, w: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        call.status == CallStatus.active
                            ? _Timer(call.activeAt, TRText.mono(12, c.text2))
                            : Text(status, style: TRText.body(12, c.text2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Local picture-in-picture
            if (peers.isNotEmpty || call.isVideo)
              Positioned(
                right: 16,
                bottom: 110,
                width: Responsive.isMobile(context) ? 110 : 220,
                height: Responsive.isMobile(context) ? 160 : 140,
                child: localTile,
              ),
            // Controls
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(TRRadius.pill),
                    border: Border.all(color: c.border),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Round(
                          icon: calls.muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: calls.muted ? 'Unmute' : 'Mute',
                          active: calls.muted,
                          onTap: calls.toggleMute,
                          size: 50,
                        ),
                        if (call.isVideo)
                          _Round(
                            icon: calls.cameraOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            label: calls.cameraOff ? 'Camera on' : 'Camera off',
                            active: calls.cameraOff,
                            onTap: calls.toggleCamera,
                            size: 50,
                          ),
                        if (call.isVideo && isPhone)
                          _Round(
                            icon: Icons.cameraswitch_rounded,
                            label: 'Switch camera',
                            onTap: calls.switchCamera,
                            size: 50,
                          ),
                        if (isPhone)
                          _Round(
                            icon: calls.speakerOn
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            label: 'Speaker',
                            active: calls.speakerOn,
                            onTap: calls.toggleSpeaker,
                            size: 50,
                          ),
                        if (canShareScreen)
                          _Round(
                            icon: calls.sharing
                                ? Icons.stop_screen_share_rounded
                                : Icons.screen_share_rounded,
                            label:
                                calls.sharing ? 'Stop sharing' : 'Share screen',
                            active: calls.sharing,
                            onTap: () => _share(context),
                            size: 50,
                          ),
                        _Round(
                          icon: Icons.call_end_rounded,
                          label: 'Hang up',
                          color: c.danger,
                          onTap: calls.hangup,
                          size: 56,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Windows / macOS: choose which screen or window to share.
class _ScreenPicker extends StatefulWidget {
  const _ScreenPicker();
  @override
  State<_ScreenPicker> createState() => _ScreenPickerState();
}

class _ScreenPickerState extends State<_ScreenPicker> {
  List<DesktopCapturerSource> _sources = [];
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    desktopCapturer
        .getSources(types: [SourceType.Screen, SourceType.Window]).then((s) {
      if (mounted)
        setState(() {
          _sources = s;
          _loading = false;
        });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return AlertDialog(
      backgroundColor: c.surface2,
      title: Text('Share your screen', style: TRText.display(18, c.text1)),
      content: SizedBox(
        width: 560,
        height: 380,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _sources.isEmpty
                ? Center(
                    child: Text(
                      'No screens found',
                      style: TRText.body(14, c.text2),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (final s in _sources)
                        InkWell(
                          onTap: () => Navigator.pop(context, s.id),
                          borderRadius: BorderRadius.circular(TRRadius.lg),
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: c.surface1,
                                    borderRadius: BorderRadius.circular(
                                      TRRadius.lg,
                                    ),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: s.thumbnail != null
                                      ? Image.memory(
                                          s.thumbnail!,
                                          fit: BoxFit.contain,
                                          gaplessPlayback: true,
                                        )
                                      : Icon(
                                          s.type == SourceType.Screen
                                              ? Icons.monitor_rounded
                                              : Icons.web_asset_rounded,
                                          color: c.text2,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TRText.body(11, c.text2),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Minimized call: draggable floating window (desktop) / pill (phone).
class _Mini extends StatefulWidget {
  final CallController calls;
  final ActiveCall call;
  const _Mini({required this.calls, required this.call});
  @override
  State<_Mini> createState() => _MiniState();
}

class _MiniState extends State<_Mini> {
  Offset? _pos;
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final size = MediaQuery.sizeOf(context);
    final w = Responsive.isMobile(context) ? size.width - 32 : 280.0;
    const h = 72.0;
    _pos ??= Offset(
      size.width - w - 16,
      MediaQuery.paddingOf(context).top + 16,
    );
    final p = Offset(
      _pos!.dx.clamp(0, size.width - w),
      _pos!.dy.clamp(0, size.height - h),
    );
    final call = widget.call;
    return Positioned(
      left: p.dx,
      top: p.dy,
      width: w,
      height: h,
      child: GestureDetector(
        onPanUpdate: kIsWeb || !isPhone
            ? (d) => setState(() => _pos = p + d.delta)
            : null,
        onTap: () => widget.calls.setMinimized(false),
        child: Material(
          color: c.surface2,
          elevation: 8,
          borderRadius: BorderRadius.circular(TRRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                TRAvatar(name: call.title, url: call.avatar, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        call.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TRText.body(14, c.text1, w: FontWeight.w600),
                      ),
                      call.status == CallStatus.active
                          ? _Timer(call.activeAt, TRText.mono(12, c.success))
                          : Text(
                              _statusText(widget.calls, call),
                              style: TRText.body(12, c.text2),
                            ),
                    ],
                  ),
                ),
                _Round(
                  icon: widget.calls.muted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  label: 'Mute',
                  active: widget.calls.muted,
                  onTap: widget.calls.toggleMute,
                  size: 40,
                ),
                _Round(
                  icon: Icons.call_end_rounded,
                  label: 'Hang up',
                  color: c.danger,
                  onTap: widget.calls.hangup,
                  size: 40,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
