import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../core/fancy.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../calls/call_controller.dart'
    show isDesktopNative, canShareScreen, isPhone;
import 'zone_controller.dart';
import 'desktop_youtube_player.dart';

/// The YouTube player works on Android, iPhone, Mac and web. Windows/Linux use the in-app desktop player.
bool get _canEmbedYouTube =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

Future<void> openZone(BuildContext context, String chatId, String title) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => ZonePage(chatId: chatId, title: title)),
    );

class ZonePage extends StatefulWidget {
  final String chatId, title;
  const ZonePage({super.key, required this.chatId, required this.title});
  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage> {
  late final ZoneController z = ZoneController(
    Supabase.instance.client,
    widget.chatId,
  );
  final Map<String, Profile> _people = {};
  final _chat = TextEditingController(), _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    z.addListener(_onChange);
  }

  void _onChange() {
    final missing =
        z.participants
            .map((p) => p.userId)
            .where((id) => !_people.containsKey(id))
            .toSet();
    for (final m in z.messages) {
      if (!_people.containsKey(m.from)) missing.add(m.from);
    }
    if (missing.isNotEmpty) {
      Supabase.instance.client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .inFilter('id', missing.toList())
          .then((rows) {
            if (!mounted) return;
            setState(() {
              for (final r in rows) {
                _people[r['id']] = Profile.fromJson(r);
              }
            });
          });
    }
    if (z.error != null) {
      final e = z.error!;
      z.error = null;
      showToast(context, e, error: true);
    }
  }

  @override
  void dispose() {
    z.removeListener(_onChange);
    z.dispose();
    _chat.dispose();
    _link.dispose();
    super.dispose();
  }

  String _name(String id) =>
      id == z.me ? 'You' : plainName(_people[id]?.displayName ?? 'Member');

  Future<void> _share() async {
    if (z.sharing) return z.stopScreenShare();
    if (isDesktopNative) {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen],
      );
      if (sources.isEmpty) return;
      await z.startScreenShare(desktopSourceId: sources.first.id);
    } else {
      await z.startScreenShare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface1,
        title: Row(
          children: [
            Icon(Icons.headphones_rounded, color: context.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${widget.title} · Zone',
                overflow: TextOverflow.ellipsis,
                style: TRText.body(16, c.text1, w: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: z,
        builder: (context, _) {
          final wide =
              !Responsive.isMobile(context) &&
              MediaQuery.sizeOf(context).width > 1000;
          final left = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _voiceCard(c),
              const SizedBox(height: 16),
              if (z.screens.isNotEmpty || z.sharing) ...[
                _screensCard(c),
                const SizedBox(height: 16),
              ],
              _musicCard(c),
              if (!wide) ...[
                const SizedBox(height: 16),
                SizedBox(height: 420, child: _chatCard(c)),
              ],
            ],
          );
          if (!wide) return left;
          return Row(
            children: [
              Expanded(child: left),
              SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                  child: _chatCard(c),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(
    TRColors c,
    String title,
    List<Widget> children, {
    Widget? trailing,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: c.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TRText.body(15, c.text1, w: FontWeight.w600),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  Widget _voiceCard(TRColors c) {
    return _card(c, 'Voice · ${z.participants.length} here', [
      if (z.participants.isEmpty)
        Text('Nobody is in the Zone yet.', style: TRText.body(13, c.text3)),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final p in z.participants)
            SizedBox(
              width: 76,
              child: Column(
                children: [
                  Stack(
                    children: [
                      TRAvatar(
                        name: _name(p.userId),
                        url: _people[p.userId]?.avatarUrl,
                        size: 56,
                      ),
                      if (p.muted || p.deafened)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: c.danger,
                            child: Icon(
                              p.deafened
                                  ? Icons.headset_off_rounded
                                  : Icons.mic_off_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _name(p.userId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TRText.body(12, c.text2),
                  ),
                ],
              ),
            ),
        ],
      ),
      if (z.reactions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          z.reactions.map((r) => r.emoji).join(' '),
          style: const TextStyle(fontSize: 28),
        ),
      ],
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!z.joined)
            TRButton(
              label: z.joining ? 'Joining…' : 'Join Zone',
              icon: Icons.headphones_rounded,
              loading: z.joining,
              onPressed: z.joining ? null : z.join,
            )
          else ...[
            TRButton(
              label: z.muted ? 'Unmute' : 'Mute',
              icon: z.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              variant: TRButtonVariant.outline,
              onPressed: z.toggleMute,
            ),
            TRButton(
              label: z.deafened ? 'Undeafen' : 'Deafen',
              icon:
                  z.deafened
                      ? Icons.headset_off_rounded
                      : Icons.headset_rounded,
              variant: TRButtonVariant.outline,
              onPressed: z.toggleDeafen,
            ),
            if (canShareScreen && !isPhone)
              TRButton(
                label: z.sharing ? 'Stop sharing' : 'Share screen',
                icon: Icons.screen_share_rounded,
                variant: TRButtonVariant.outline,
                onPressed: _share,
              ),
            for (final e in const ['👍', '😂', '🔥', '❤️', '🎉'])
              InkWell(
                onTap: () => z.react(e),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              ),
            TRButton(
              label: 'Leave',
              icon: Icons.logout_rounded,
              variant: TRButtonVariant.danger,
              onPressed: z.leave,
            ),
          ],
        ],
      ),
    ]);
  }

  Widget _screensCard(TRColors c) => _card(c, 'Screens', [
    if (z.sharing)
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TRRadius.x2l),
          child: RTCVideoView(
            z.localScreen,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
        ),
      ),
    for (final e in z.screens.entries) ...[
      const SizedBox(height: 8),
      Text('${_name(e.key)} is sharing', style: TRText.body(12, c.text2)),
      const SizedBox(height: 4),
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TRRadius.x2l),
          child: RTCVideoView(
            e.value,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
        ),
      ),
    ],
  ]);

  Widget _musicCard(TRColors c) {
    final zone = z.zone;
    final vid = zone?['current_video_id'] as String?;
    return _card(c, 'Watch together', [
      if (vid == null)
        Text(
          'Nothing playing. Paste a YouTube link to start.',
          style: TRText.body(13, c.text3),
        )
      else ...[
        if (_canEmbedYouTube && z.joined)
          _SyncedPlayer(key: ValueKey(vid), z: z, videoId: vid)
        else if (z.joined &&
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux))
          DesktopSyncedPlayer(key: ValueKey('d$vid'), z: z, videoId: vid)
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                zone?['current_video_thumb'] != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        zone!['current_video_thumb'],
                        width: 64,
                        fit: BoxFit.cover,
                      ),
                    )
                    : const Icon(Icons.music_note_rounded),
            title: Text(
              zone?['current_video_title'] ?? 'Playing',
              style: TRText.body(14, c.text1),
            ),
            subtitle: Text(
              z.joined
                  ? 'Opens in YouTube on this device'
                  : 'Join the Zone to listen together',
              style: TRText.body(12, c.text3),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed:
                  () => launchUrl(
                    Uri.parse(
                      'https://www.youtube.com/watch?v=$vid&t=${z.musicPosition.floor()}s',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          zone?['current_video_title'] ?? '',
          style: TRText.body(14, c.text1, w: FontWeight.w600),
        ),
        if (z.joined)
          Row(
            children: [
              IconButton(
                icon: Icon(
                  zone?['is_playing'] == true
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: z.togglePlay,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded),
                tooltip: 'Skip',
                onPressed: z.skip,
              ),
            ],
          ),
      ],
      if (z.joined) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TRTextField(
                controller: _link,
                hint: 'YouTube link',
                icon: Icons.link_rounded,
              ),
            ),
            const SizedBox(width: 8),
            TRButton(
              label: 'Add',
              onPressed: () async {
                final err = await z.addTrack(_link.text);
                if (!mounted) return;
                if (err != null) {
                  showToast(context, err, error: true);
                } else {
                  _link.clear();
                }
              },
            ),
          ],
        ),
      ],
      if (z.queue.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Up next', style: TRText.body(12, c.text3, w: FontWeight.w700)),
        for (final q in z.queue)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading:
                q.thumbnail != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        q.thumbnail!,
                        width: 48,
                        fit: BoxFit.cover,
                      ),
                    )
                    : null,
            title: Text(
              q.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TRText.body(13, c.text1),
            ),
            subtitle: Text(
              'Added by ${_name(q.addedBy)}',
              style: TRText.body(11, c.text3),
            ),
            trailing:
                z.joined
                    ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => z.removeTrack(q.id),
                    )
                    : null,
          ),
      ],
    ]);
  }

  Widget _chatCard(TRColors c) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: c.border)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Text(
              'Zone chat',
              style: TRText.body(15, c.text1, w: FontWeight.w600),
            ),
          ],
        ),
        Text(
          'Only people in the Zone see this. It is not saved.',
          style: TRText.body(11, c.text3),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            reverse: true,
            children: [
              for (final m in z.messages.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: RichText(
                    text: TextSpan(
                      style: TRText.body(13, c.text1),
                      children: [
                        TextSpan(
                          text: '${_name(m.from)}  ',
                          style: TRText.body(
                            13,
                            context.accent,
                            w: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: m.text),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (z.joined)
          Row(
            children: [
              Expanded(
                child: TRTextField(
                  controller: _chat,
                  hint: 'Say something…',
                  maxLength: 500,
                  onSubmitted: (v) {
                    z.sendChat(v);
                    _chat.clear();
                  },
                ),
              ),
              TRIconButton(
                icon: Icons.send_rounded,
                tooltip: 'Send',
                onPressed: () {
                  z.sendChat(_chat.text);
                  _chat.clear();
                },
              ),
            ],
          )
        else
          Text('Join to chat.', style: TRText.body(12, c.text3)),
      ],
    ),
  );
}

/// Embedded YouTube that keeps itself in step with the Zone's shared timeline.
class _SyncedPlayer extends StatefulWidget {
  final ZoneController z;
  final String videoId;
  const _SyncedPlayer({super.key, required this.z, required this.videoId});
  @override
  State<_SyncedPlayer> createState() => _SyncedPlayerState();
}

class _SyncedPlayerState extends State<_SyncedPlayer> {
  late final YoutubePlayerController _yt = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    startSeconds: widget.z.musicPosition,
    params: const YoutubePlayerParams(
      showControls: false,
      showFullscreenButton: false,
      mute: false,
    ),
  );
  Timer? _sync;

  @override
  void initState() {
    super.initState();
    _sync = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    widget.z.addListener(_check);
  }

  Future<void> _check() async {
    final playing = widget.z.zone?['is_playing'] == true;
    try {
      if (!playing) {
        await _yt.pauseVideo();
        return;
      }
      final cur = await _yt.currentTime;
      final want = widget.z.musicPosition;
      if ((cur - want).abs() > 3)
        await _yt.seekTo(seconds: want, allowSeekAhead: true);
      if ((await _yt.playerState) != PlayerState.playing) await _yt.playVideo();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sync?.cancel();
    widget.z.removeListener(_check);
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(TRRadius.x2l),
    child: YoutubePlayer(controller: _yt, aspectRatio: 16 / 9),
  );
}
