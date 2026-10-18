import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Zones — always-on voice room per chat. Port of hooks/use-zone.tsx.
/// Speaks the website's protocol on `zone-rtc:<zoneId>` (hello / offer / answer /
/// ice / bye / screen / chat / react / music-sync), so app and website users
/// share the same room. DB tables: zones, zone_participants, zone_queue.

class ZoneParticipant {
  final String userId;
  final bool muted, deafened;
  final DateTime joinedAt;
  ZoneParticipant.fromJson(Map<String, dynamic> j)
      : userId = j['user_id'],
        muted = j['is_muted'] == true,
        deafened = j['is_deafened'] == true,
        joinedAt = DateTime.tryParse(j['joined_at'] ?? '') ?? DateTime.now();
}

class ZoneQueueItem {
  final String id, videoId, title, addedBy;
  final String? thumbnail;
  final int position;
  final DateTime createdAt;
  ZoneQueueItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        videoId = j['video_id'],
        title = j['title'] ?? 'Track',
        addedBy = j['added_by'] ?? '',
        thumbnail = j['thumbnail'],
        position = (j['position'] as num?)?.toInt() ?? 0,
        createdAt = DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now();
}

class ZoneChatMsg {
  final String id, from, text;
  final int at;
  ZoneChatMsg(this.id, this.from, this.text, this.at);
}

class ZoneReaction {
  final String id, from, emoji;
  ZoneReaction(this.id, this.from, this.emoji);
}

class _Peer {
  final RTCPeerConnection pc;
  final RTCVideoRenderer audio = RTCVideoRenderer();
  RTCVideoRenderer? screen;
  final List<RTCIceCandidate> pending = [];
  _Peer(this.pc);
}

String _id() {
  final r = Random.secure();
  return List.generate(
    12,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Map<String, dynamic> _payloadOf(dynamic msg) {
  final m = (msg is Map) ? Map<String, dynamic>.from(msg) : <String, dynamic>{};
  if (m['payload'] is Map) {
    final p = Map<String, dynamic>.from(m['payload']);
    if (p['payload'] is Map && p.containsKey('event'))
      return Map<String, dynamic>.from(p['payload']);
    return p;
  }
  return m;
}

const _ice = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun.cloudflare.com:3478'},
  {
    'urls': [
      'turn:openrelay.metered.ca:80',
      'turn:openrelay.metered.ca:443',
      'turn:openrelay.metered.ca:443?transport=tcp',
    ],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];

String? parseYouTubeId(String input) {
  final t = input.trim();
  final idRe = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  if (idRe.hasMatch(t)) return t;
  final u = Uri.tryParse(t);
  if (u == null) return null;
  if (u.host == 'youtu.be') {
    final id = u.pathSegments.isNotEmpty ? u.pathSegments.first : '';
    return idRe.hasMatch(id) ? id : null;
  }
  if (u.host.endsWith('youtube.com') ||
      u.host.endsWith('youtube-nocookie.com')) {
    final v = u.queryParameters['v'];
    if (v != null && idRe.hasMatch(v)) return v;
    final m = RegExp(
      r'/(?:shorts|embed)/([a-zA-Z0-9_-]{11})',
    ).firstMatch(u.path);
    if (m != null) return m.group(1);
  }
  return null;
}

class ZoneController extends ChangeNotifier {
  final SupabaseClient db;
  final String chatId;
  ZoneController(this.db, this.chatId) {
    _loadPassive();
  }

  String? get me => db.auth.currentUser?.id;
  String? zoneId;
  Map<String, dynamic>? zone;
  List<ZoneParticipant> participants = [];
  List<ZoneQueueItem> queue = [];
  final List<ZoneChatMsg> messages = [];
  final List<ZoneReaction> reactions = [];
  final Map<String, _Peer> _peers = {};
  bool joined = false,
      joining = false,
      muted = false,
      deafened = false,
      sharing = false;
  String? error;

  MediaStream? _mic, _screenStream;
  final RTCVideoRenderer localScreen = RTCVideoRenderer();
  bool _localScreenReady = false;
  RealtimeChannel? _rtc, _dbCh;

  Map<String, RTCVideoRenderer> get screens => {
        for (final e in _peers.entries)
          if (e.value.screen != null) e.key: e.value.screen!,
      };

  // ---------------------------------------------------------------- data
  Future<void> _loadPassive() async {
    try {
      final z =
          await db.from('zones').select().eq('chat_id', chatId).maybeSingle();
      if (z == null) return;
      zoneId = z['id'];
      zone = z;
      await _refreshLists();
      _watchDb();
      notifyListeners();
    } catch (e) {
      debugPrint('[zone] load: $e');
    }
  }

  Future<void> _refreshLists() async {
    final id = zoneId;
    if (id == null) return;
    final res = await Future.wait([
      db.from('zone_participants').select().eq('zone_id', id),
      db
          .from('zone_queue')
          .select()
          .eq('zone_id', id)
          .order('position')
          .order('created_at'),
    ]);
    participants = [for (final r in res[0]) ZoneParticipant.fromJson(r)];
    queue = [for (final r in res[1]) ZoneQueueItem.fromJson(r)];
  }

  void _watchDb() {
    final id = zoneId;
    if (id == null || _dbCh != null) return;
    _dbCh = db
        .channel('zone-db:$id:${_id()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zone_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'zone_id',
            value: id,
          ),
          callback: (_) => _refreshLists().then((_) => notifyListeners()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'zone_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'zone_id',
            value: id,
          ),
          callback: (_) => _refreshLists().then((_) => notifyListeners()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'zones',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: id,
          ),
          callback: (p) {
            zone = p.newRecord;
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Seconds into the current track, derived like the website.
  double get musicPosition {
    final z = zone;
    if (z == null) return 0;
    final base = (z['current_position_sec'] as num?)?.toDouble() ?? 0;
    final started = DateTime.tryParse(z['current_started_at'] ?? '');
    if (z['is_playing'] == true && started != null) {
      return base +
          max(0, DateTime.now().difference(started).inMilliseconds / 1000);
    }
    return base;
  }

  // ---------------------------------------------------------------- join / leave
  Future<void> join() async {
    final uid = me;
    if (uid == null || joined || joining) return;
    joining = true;
    error = null;
    notifyListeners();
    try {
      final zid =
          await db.rpc('ensure_zone', params: {'_chat_id': chatId}) as String;
      zoneId = zid;
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      _applyMic();
      await db.from('zone_participants').upsert({
        'zone_id': zid,
        'user_id': uid,
        'joined_at': DateTime.now().toUtc().toIso8601String(),
      });
      zone = await db.from('zones').select().eq('id', zid).maybeSingle();
      await _refreshLists();
      _watchDb();

      final ch = db.channel(
        'zone-rtc:$zid',
        opts: const RealtimeChannelConfig(self: false),
      );
      _rtc = ch;
      ch.onBroadcast(
        event: 'hello',
        callback: (m) {
          final p = _payloadOf(m);
          final from = p['from'];
          if (from is String && from != uid && !_peers.containsKey(from))
            _createPeer(from, true);
        },
      );
      ch.onBroadcast(event: 'offer', callback: (m) => _onOffer(_payloadOf(m)));
      ch.onBroadcast(
        event: 'answer',
        callback: (m) => _onAnswer(_payloadOf(m)),
      );
      ch.onBroadcast(event: 'ice', callback: (m) => _onIce(_payloadOf(m)));
      ch.onBroadcast(
        event: 'bye',
        callback: (m) {
          final from = _payloadOf(m)['from'];
          if (from is String) _closePeer(from);
          notifyListeners();
        },
      );
      ch.onBroadcast(
        event: 'screen',
        callback: (m) {
          final p = _payloadOf(m);
          if (p['on'] == false && p['from'] is String) {
            final peer = _peers[p['from']];
            peer?.screen?.srcObject = null;
            peer?.screen?.dispose();
            peer?.screen = null;
            notifyListeners();
          }
        },
      );
      ch.onBroadcast(
        event: 'music-sync',
        callback: (m) async {
          zone = await db.from('zones').select().eq('id', zid).maybeSingle();
          notifyListeners();
        },
      );
      ch.onBroadcast(
        event: 'chat',
        callback: (m) {
          final p = _payloadOf(m);
          if (p['id'] is! String || p['text'] is! String) return;
          if (messages.any((x) => x.id == p['id'])) return;
          messages.add(
            ZoneChatMsg(
              p['id'],
              p['from'] ?? '',
              p['text'],
              (p['at'] as num?)?.toInt() ?? 0,
            ),
          );
          if (messages.length > 200) messages.removeAt(0);
          notifyListeners();
        },
      );
      ch.onBroadcast(
        event: 'react',
        callback: (m) => _showReaction(_payloadOf(m)),
      );

      final ready = Completer<void>();
      ch.subscribe((s, _) {
        if (s == RealtimeSubscribeStatus.subscribed && !ready.isCompleted)
          ready.complete();
        if ((s == RealtimeSubscribeStatus.channelError ||
                s == RealtimeSubscribeStatus.timedOut) &&
            !ready.isCompleted) {
          ready.completeError(
            Exception('Could not connect to the Zone. Please try again.'),
          );
        }
      });
      await ready.future.timeout(const Duration(seconds: 15));
      await ch.sendBroadcastMessage(event: 'hello', payload: {'from': uid});
      joined = true;
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
      await _teardown();
    } finally {
      joining = false;
      notifyListeners();
    }
  }

  Future<void> leave() async {
    if (!joined) return;
    try {
      await _rtc?.sendBroadcastMessage(event: 'bye', payload: {'from': me});
    } catch (_) {}
    await _teardown();
    notifyListeners();
  }

  Future<void> _teardown() async {
    for (final id in _peers.keys.toList()) {
      _closePeer(id);
    }
    if (sharing) await stopScreenShare(announce: false);
    for (final t in _mic?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    _mic = null;
    if (_rtc != null) await db.removeChannel(_rtc!);
    _rtc = null;
    final zid = zoneId, uid = me;
    if (zid != null && uid != null) {
      try {
        await db
            .from('zone_participants')
            .delete()
            .eq('zone_id', zid)
            .eq('user_id', uid);
      } catch (_) {}
    }
    joined = false;
    muted = deafened = false;
  }

  // ---------------------------------------------------------------- peers
  Future<_Peer?> _createPeer(String peerId, bool initiator) async {
    final uid = me;
    if (uid == null || _rtc == null) return null;
    final existing = _peers[peerId];
    if (existing != null) return existing;
    final pc = await createPeerConnection({
      'iceServers': _ice,
      'sdpSemantics': 'unified-plan',
    });
    final peer = _Peer(pc);
    _peers[peerId] = peer;
    await peer.audio.initialize();
    for (final t in _mic?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, _mic!);
    }
    for (final t in _screenStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, _screenStream!);
    }
    pc.onTrack = (e) async {
      if (e.streams.isEmpty) return;
      if (e.track.kind == 'video') {
        if (peer.screen == null) {
          peer.screen = RTCVideoRenderer();
          await peer.screen!.initialize();
        }
        peer.screen!.srcObject = e.streams.first;
      } else {
        peer.audio.srcObject = e.streams.first; // plays automatically
        e.track.enabled = !deafened;
      }
      notifyListeners();
    };
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _rtc?.sendBroadcastMessage(
        event: 'ice',
        payload: {
          'from': uid,
          'to': peerId,
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        },
      );
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed)
        pc.restartIce();
    };
    // Renegotiate when tracks change (e.g. screen share added later).
    pc.onRenegotiationNeeded = () {
      if (initiator ||
          pc.signalingState == RTCSignalingState.RTCSignalingStateStable)
        _negotiate(peerId, pc);
    };
    if (initiator) await _negotiate(peerId, pc);
    return peer;
  }

  Future<void> _negotiate(String peerId, RTCPeerConnection pc) async {
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _rtc?.sendBroadcastMessage(
      event: 'offer',
      payload: {
        'from': me,
        'to': peerId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      },
    );
  }

  Future<void> _drain(String from, RTCPeerConnection pc) async {
    final peer = _peers[from];
    if (peer == null) return;
    for (final c in List.of(peer.pending)) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    peer.pending.clear();
  }

  Future<void> _onOffer(Map<String, dynamic> p) async {
    final from = p['from'], uid = me;
    if (from is! String || p['to'] != uid || p['sdp'] is! Map) return;
    final peer = _peers[from] ?? await _createPeer(from, false);
    if (peer == null) return;
    final pc = peer.pc;
    try {
      // Both offered at once: the higher id keeps its offer (website rule).
      if (pc.signalingState ==
          RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        if (uid!.compareTo(from) > 0) return;
        await pc.setLocalDescription(RTCSessionDescription(null, 'rollback'));
      }
      final sdp = Map<String, dynamic>.from(p['sdp']);
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      await _drain(from, pc);
      final ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      await _rtc?.sendBroadcastMessage(
        event: 'answer',
        payload: {
          'from': uid,
          'to': from,
          'sdp': {'type': ans.type, 'sdp': ans.sdp},
        },
      );
    } catch (e) {
      debugPrint('[zone] offer failed $e');
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> p) async {
    final from = p['from'];
    if (from is! String || p['to'] != me) return;
    final pc = _peers[from]?.pc;
    if (pc == null ||
        pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer)
      return;
    final sdp = Map<String, dynamic>.from(p['sdp']);
    await pc.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'], sdp['type']),
    );
    await _drain(from, pc);
  }

  Future<void> _onIce(Map<String, dynamic> p) async {
    final from = p['from'];
    if (from is! String || p['to'] != me) return;
    final c = Map<String, dynamic>.from(p['candidate'] ?? {});
    final ice = RTCIceCandidate(
      c['candidate'],
      c['sdpMid'],
      (c['sdpMLineIndex'] as num?)?.toInt(),
    );
    final peer = _peers[from];
    if (peer == null) return;
    final remote = await peer.pc.getRemoteDescription();
    if (remote == null) {
      peer.pending.add(ice);
      return;
    }
    try {
      await peer.pc.addCandidate(ice);
    } catch (_) {}
  }

  void _closePeer(String id) {
    final p = _peers.remove(id);
    if (p == null) return;
    p.pc.close();
    p.audio.srcObject = null;
    p.audio.dispose();
    p.screen?.dispose();
  }

  // ---------------------------------------------------------------- controls
  void _applyMic() {
    for (final t in _mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted && !deafened;
    }
  }

  Future<void> toggleMute() async {
    muted = !muted;
    _applyMic();
    notifyListeners();
    await db
        .from('zone_participants')
        .update({'is_muted': muted})
        .eq('zone_id', zoneId!)
        .eq('user_id', me!);
  }

  Future<void> toggleDeafen() async {
    deafened = !deafened;
    if (deafened) muted = true;
    _applyMic();
    for (final p in _peers.values) {
      for (final t
          in p.audio.srcObject?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = !deafened;
      }
    }
    notifyListeners();
    await db
        .from('zone_participants')
        .update({'is_deafened': deafened, 'is_muted': muted})
        .eq('zone_id', zoneId!)
        .eq('user_id', me!);
  }

  Future<void> startScreenShare({String? desktopSourceId}) async {
    if (!joined || sharing) return;
    try {
      _screenStream = await navigator.mediaDevices.getDisplayMedia(
        desktopSourceId != null
            ? {
                'video': {
                  'deviceId': {'exact': desktopSourceId},
                  'mandatory': {'frameRate': 30.0},
                },
                'audio': false,
              }
            : {'video': true, 'audio': false},
      );
      if (!_localScreenReady) {
        await localScreen.initialize();
        _localScreenReady = true;
      }
      localScreen.srcObject = _screenStream;
      final track = _screenStream!.getVideoTracks().first;
      track.onEnded = () => stopScreenShare();
      for (final p in _peers.values) {
        await p.pc.addTrack(track, _screenStream!); // triggers renegotiation
      }
      sharing = true;
      await _rtc?.sendBroadcastMessage(
        event: 'screen',
        payload: {'from': me, 'on': true},
      );
      notifyListeners();
    } catch (_) {
      error = 'Screen sharing was cancelled or is not allowed.';
      notifyListeners();
    }
  }

  Future<void> stopScreenShare({bool announce = true}) async {
    if (!sharing) return;
    for (final p in _peers.values) {
      for (final s in await p.pc.getSenders()) {
        if (s.track?.kind == 'video') await p.pc.removeTrack(s);
      }
    }
    for (final t in _screenStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    _screenStream = null;
    if (_localScreenReady) localScreen.srcObject = null;
    sharing = false;
    if (announce)
      await _rtc?.sendBroadcastMessage(
        event: 'screen',
        payload: {'from': me, 'on': false},
      );
    notifyListeners();
  }

  Future<void> sendChat(String text) async {
    final t = text.trim();
    if (t.isEmpty || !joined) return;
    final m = {
      'id': _id(),
      'from': me,
      'text': t.length > 500 ? t.substring(0, 500) : t,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    messages.add(
      ZoneChatMsg(m['id'] as String, me!, m['text'] as String, m['at'] as int),
    );
    notifyListeners();
    await _rtc?.sendBroadcastMessage(event: 'chat', payload: m);
  }

  void _showReaction(Map<String, dynamic> p) {
    if (p['id'] is! String || p['emoji'] is! String) return;
    if (reactions.any((x) => x.id == p['id'])) return;
    final r = ZoneReaction(p['id'], p['from'] ?? '', p['emoji']);
    reactions.add(r);
    notifyListeners();
    Timer(const Duration(milliseconds: 2400), () {
      reactions.remove(r);
      notifyListeners();
    });
  }

  Future<void> react(String emoji) async {
    final r = {
      'id': _id(),
      'from': me,
      'emoji': emoji,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _showReaction(r);
    await _rtc?.sendBroadcastMessage(event: 'react', payload: r);
  }

  // ---------------------------------------------------------------- music
  Future<bool> _publish(Map<String, dynamic> patch) async {
    final id = zoneId;
    if (id == null) return false;
    try {
      await db.from('zones').update({
        ...patch,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      zone = {...?zone, ...patch};
      notifyListeners();
      await _rtc?.sendBroadcastMessage(
        event: 'music-sync',
        payload: {'from': me ?? '', 'zone': zone},
      );
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<String?> addTrack(String link) async {
    final vid = parseYouTubeId(link);
    if (vid == null) return 'Paste a YouTube link.';
    if (zoneId == null) return 'Join the Zone first.';
    var title = 'YouTube video';
    var thumb = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
    try {
      final r = await http.get(
        Uri.parse(
          'https://noembed.com/embed?url=${Uri.encodeComponent('https://www.youtube.com/watch?v=$vid')}',
        ),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        title = (j['title'] as String?) ?? title;
        thumb = (j['thumbnail_url'] as String?) ?? thumb;
      }
    } catch (_) {}
    if (zone?['current_video_id'] == null) {
      await _publish({
        'current_video_id': vid,
        'current_video_title': title,
        'current_video_thumb': thumb,
        'current_position_sec': 0,
        'current_started_at': DateTime.now().toUtc().toIso8601String(),
        'is_playing': true,
      });
      return null;
    }
    final maxPos = queue.fold<int>(0, (m, q) => max(m, q.position));
    try {
      await db.from('zone_queue').insert({
        'zone_id': zoneId,
        'video_id': vid,
        'title': title,
        'thumbnail': thumb,
        'added_by': me,
        'position': maxPos + 1,
      });
    } catch (e) {
      return '$e';
    }
    return null;
  }

  Future<void> removeTrack(String id) async {
    queue.removeWhere((q) => q.id == id);
    notifyListeners();
    await db.from('zone_queue').delete().eq('id', id);
  }

  Future<void> skip() async {
    if (queue.isNotEmpty) {
      final next = queue.first;
      queue.remove(next);
      await db
          .from('zone_queue')
          .delete()
          .eq('zone_id', zoneId!)
          .eq('id', next.id);
      await _publish({
        'current_video_id': next.videoId,
        'current_video_title': next.title,
        'current_video_thumb': next.thumbnail,
        'current_position_sec': 0,
        'current_started_at': DateTime.now().toUtc().toIso8601String(),
        'is_playing': true,
      });
    } else {
      await _publish({
        'current_video_id': null,
        'current_video_title': null,
        'current_video_thumb': null,
        'current_position_sec': 0,
        'current_started_at': null,
        'is_playing': false,
      });
    }
  }

  Future<void> togglePlay() async {
    if (zone?['current_video_id'] == null) return;
    final playing = zone!['is_playing'] == true;
    await _publish({
      'is_playing': !playing,
      'current_position_sec': musicPosition,
      'current_started_at': !playing
          ? DateTime.now().toUtc().toIso8601String()
          : zone!['current_started_at'],
    });
  }

  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    leave();
    if (_dbCh != null) db.removeChannel(_dbCh!);
    if (_localScreenReady) localScreen.dispose();
    super.dispose();
  }
}
