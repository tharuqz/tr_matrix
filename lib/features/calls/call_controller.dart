import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/auth_service.dart';
import 'ringer.dart';

/// Calls — port of components/calls/call-context.tsx.
///
/// * 1-to-1 calls speak the SAME signaling protocol as the website
///   (`user:<id>` inbox + `call:<id>` channel, events call-invite / accept /
///   reject / offer / answer / ice / hangup), so app <-> website calls work.
/// * Group calls (new) use a "mesh": every person connects directly to every
///   other person over `gcall:<id>`. Up to ~6 people works well. The website
///   does not know this protocol yet, so group calls are app <-> app only.

enum CallStatus { incoming, outgoing, connecting, active }

class CallPeer {
  final String userId;
  String name;
  String? avatar;
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  bool rendererReady = false;
  bool hasVideo = false;
  bool remoteSet = false;
  final List<RTCIceCandidate> pendingIce = [];
  bool connected = false;
  CallPeer(this.userId, this.name, this.avatar);
}

class ActiveCall {
  final String callId;
  final String kind; // voice | video
  final String chatId;
  final bool isGroup;
  final bool isCaller;
  final String title;
  final String? avatar;
  final String? peerUserId; // 1:1 only
  CallStatus status;
  final DateTime startedAt = DateTime.now();
  DateTime? activeAt;
  ActiveCall({
    required this.callId,
    required this.kind,
    required this.chatId,
    required this.isGroup,
    required this.isCaller,
    required this.title,
    this.avatar,
    this.peerUserId,
    required this.status,
  });
  bool get isVideo => kind == 'video';
}

class GroupInvitee {
  final String userId, name;
  final String? avatar;
  GroupInvitee(this.userId, this.name, this.avatar);
}

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Same unwrapping rules as the website's payloadOf().
Map<String, dynamic> _payloadOf(dynamic msg) {
  var m = (msg is Map) ? Map<String, dynamic>.from(msg) : <String, dynamic>{};
  if (m['payload'] is Map) {
    final p = Map<String, dynamic>.from(m['payload']);
    if (p['payload'] is Map && p.containsKey('event')) return Map<String, dynamic>.from(p['payload']);
    return p;
  }
  return m;
}

const _iceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
  {'urls': 'stun:stun.cloudflare.com:3478'},
  {
    'urls': [
      'turn:openrelay.metered.ca:80',
      'turn:openrelay.metered.ca:443',
      'turn:openrelay.metered.ca:443?transport=tcp',
      'turns:openrelay.metered.ca:443',
    ],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];

bool get canShareScreen => kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;
bool get isPhone => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
bool get isDesktopNative =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

class CallController extends ChangeNotifier {
  final SupabaseClient db;
  final AuthService auth;
  final Ringer _ringer = Ringer();
  CallController(this.db, this.auth) {
    auth.addListener(_onAuth);
    _onAuth();
  }

  ActiveCall? call;
  final Map<String, CallPeer> peers = {};
  MediaStream? localStream;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  bool _localReady = false;
  bool muted = false, cameraOff = false, speakerOn = true, sharing = false, minimized = false;
  String? error;

  RealtimeChannel? _inbox;
  String? _inboxUser;
  RealtimeChannel? _callCh;
  Timer? _ringTimeout;
  MediaStreamTrack? _camTrack;
  int _joinedAt = 0;
  String _outcome = '';

  String? get _me => auth.user?.id;
  List<CallPeer> get peerList => peers.values.toList();

  // ---------------------------------------------------------------- inbox
  void _onAuth() {
    final uid = _me;
    if (uid == _inboxUser) return;
    if (_inbox != null) db.removeChannel(_inbox!);
    _inbox = null;
    _inboxUser = uid;
    if (uid == null) return;
    final ch = db.channel('user:$uid', opts: const RealtimeChannelConfig(self: false, ack: false));
    ch.onBroadcast(event: 'call-invite', callback: (m) => _onInvite(_payloadOf(m), false));
    ch.onBroadcast(event: 'group-call-invite', callback: (m) => _onInvite(_payloadOf(m), true));
    ch.onBroadcast(
      event: 'answered-elsewhere',
      callback: (m) {
        final p = _payloadOf(m);
        if (call != null && call!.callId == p['callId'] && call!.status == CallStatus.incoming) {
          _outcome = 'answered_elsewhere';
          _cleanup();
        }
      },
    );
    ch.subscribe();
    _inbox = ch;
  }

  void _onInvite(Map<String, dynamic> p, bool group) {
    if (p['callId'] is! String || p['fromUserId'] is! String) return;
    if (call != null) return; // already busy
    call = ActiveCall(
      callId: p['callId'],
      kind: p['kind'] == 'video' ? 'video' : 'voice',
      chatId: (p['chatId'] as String?) ?? '',
      isGroup: group,
      isCaller: false,
      title: group
          ? ((p['groupTitle'] as String?) ?? 'Group call')
          : ((p['fromName'] as String?)?.isNotEmpty == true ? p['fromName'] : 'Someone'),
      avatar: group ? null : p['fromAvatar'] as String?,
      peerUserId: group ? null : p['fromUserId'],
      status: CallStatus.incoming,
    );
    if (group) _groupInviter = (p['fromName'] as String?) ?? 'Someone';
    _outcome = '';
    minimized = false;
    _ringer.startIncoming();
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (call?.status == CallStatus.incoming) _cleanup();
    });
    notifyListeners();
  }

  String? _groupInviter;
  String? get groupInviter => _groupInviter;

  // ---------------------------------------------------------------- media
  Future<MediaStream> _getMedia(String kind) async {
    final video = kind == 'video';
    Future<MediaStream> req(bool v) => navigator.mediaDevices.getUserMedia({
          'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
          'video': v ? {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}} : false,
        });
    MediaStream s;
    try {
      s = await req(video);
    } catch (e) {
      if (!video) throw Exception('Microphone permission denied or no microphone found.');
      s = await req(false); // camera missing/busy → audio only
    }
    if (!_localReady) {
      await localRenderer.initialize();
      _localReady = true;
    }
    localRenderer.srcObject = s;
    localStream = s;
    if (isPhone) {
      speakerOn = video;
      await Helper.setSpeakerphoneOn(speakerOn);
    }
    return s;
  }

  Future<CallPeer> _peer(String userId, {String name = '', String? avatar}) async {
    final existing = peers[userId];
    if (existing != null && existing.pc != null) return existing;
    final peer = existing ?? CallPeer(userId, name, avatar);
    peers[userId] = peer;
    if (!peer.rendererReady) {
      await peer.renderer.initialize();
      peer.rendererReady = true;
    }
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    peer.pc = pc;
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, localStream!);
    }
    // Voice calls still reserve a video slot so screen sharing can start later.
    if (call?.isVideo != true || (localStream?.getVideoTracks().isEmpty ?? true)) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
    }
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) peer.renderer.srcObject = e.streams.first;
      if (e.track.kind == 'video') peer.hasVideo = true;
      notifyListeners();
    };
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      final body = <String, dynamic>{
        'callId': call?.callId,
        'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex},
      };
      if (call?.isGroup == true) body.addAll({'from': _me, 'to': userId});
      _send('ice', body);
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        peer.connected = true;
        if (call != null && call!.status != CallStatus.active) {
          call!.status = CallStatus.active;
          call!.activeAt = DateTime.now();
          _ringer.stop();
          _ringTimeout?.cancel();
        }
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        pc.restartIce();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        peer.connected = false;
      }
      notifyListeners();
    };
    return peer;
  }

  Future<void> _drain(CallPeer p) async {
    for (final c in List.of(p.pendingIce)) {
      try {
        await p.pc?.addCandidate(c);
      } catch (_) {}
    }
    p.pendingIce.clear();
  }

  Future<void> _send(String event, Map<String, dynamic> body) async {
    final ch = _callCh;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: event, payload: {'v': 1, ...body});
    } catch (e) {
      debugPrint('[call] send $event failed: $e');
    }
  }

  Future<void> _sendTo(String topic, String event, Map<String, dynamic> body) async {
    final ch = db.channel(topic, opts: const RealtimeChannelConfig(self: false, ack: false));
    final ready = Completer<void>();
    ch.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) ready.complete();
    });
    await ready.future.timeout(const Duration(seconds: 6), onTimeout: () {});
    try {
      await ch.sendBroadcastMessage(event: event, payload: {'v': 1, ...body});
    } finally {
      unawaited(Future.delayed(const Duration(seconds: 1), () => db.removeChannel(ch)));
    }
  }

  Future<void> _subscribeCall(String topic) async {
    final ch = db.channel(topic, opts: const RealtimeChannelConfig(self: false, ack: false));
    _callCh = ch;
    _wire(ch);
    final ready = Completer<void>();
    ch.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) ready.complete();
    });
    await ready.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  bool _forMe(Map<String, dynamic> p) => call?.isGroup != true || p['to'] == null || p['to'] == _me;
  String _fromOf(Map<String, dynamic> p) => call?.isGroup == true ? (p['from'] as String? ?? '') : (call?.peerUserId ?? '');

  void _wire(RealtimeChannel ch) {
    ch.onBroadcast(event: 'accept', callback: (_) async {
      // 1:1 — callee accepted, caller makes the offer (website behaviour).
      final c = call;
      if (c == null || c.isGroup || !c.isCaller) return;
      c.status = CallStatus.connecting;
      _ringer.stop();
      notifyListeners();
      final peer = peers[c.peerUserId];
      final pc = peer?.pc;
      if (pc == null) return;
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _send('offer', {'callId': c.callId, 'sdp': {'type': offer.type, 'sdp': offer.sdp}});
    });
    ch.onBroadcast(event: 'reject', callback: (m) {
      final c = call;
      if (c == null) return;
      if (!c.isGroup) {
        _outcome = c.isCaller ? 'cancelled' : 'declined';
        _cleanup(toast: 'Call declined');
      }
    });
    ch.onBroadcast(event: 'hangup', callback: (_) {
      if (call?.isGroup == true) return;
      _cleanup(toast: 'Call ended');
    });
    ch.onBroadcast(event: 'leave', callback: (m) {
      final p = _payloadOf(m);
      final uid = p['userId'] as String?;
      if (uid == null) return;
      _closePeer(uid);
      notifyListeners();
    });
    ch.onBroadcast(event: 'join', callback: (m) async {
      // Group: earlier joiners offer to later joiners (avoids both sides offering).
      final p = _payloadOf(m);
      final uid = p['userId'] as String?;
      final at = (p['joinedAt'] as num?)?.toInt() ?? 0;
      if (uid == null || uid == _me || call?.isGroup != true || _joinedAt == 0) return;
      final iAmEarlier = _joinedAt < at || (_joinedAt == at && (_me ?? '').compareTo(uid) < 0);
      if (!iAmEarlier) return;
      final peer = await _peer(uid, name: p['name'] ?? 'Member', avatar: p['avatar']);
      if (call!.status == CallStatus.outgoing) call!.status = CallStatus.connecting;
      final offer = await peer.pc!.createOffer();
      await peer.pc!.setLocalDescription(offer);
      await _send('offer', {
        'callId': call!.callId,
        'from': _me,
        'to': uid,
        'name': auth.profile?.displayName,
        'avatar': auth.profile?.avatarUrl,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      notifyListeners();
    });
    ch.onBroadcast(event: 'offer', callback: (m) async {
      final p = _payloadOf(m);
      if (!_forMe(p) || call == null) return;
      final from = _fromOf(p);
      final peer = await _peer(from, name: p['name'] ?? call!.title, avatar: p['avatar']);
      final sdp = Map<String, dynamic>.from(p['sdp']);
      await peer.pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
      peer.remoteSet = true;
      await _drain(peer);
      final answer = await peer.pc!.createAnswer();
      await peer.pc!.setLocalDescription(answer);
      final body = <String, dynamic>{'callId': call!.callId, 'sdp': {'type': answer.type, 'sdp': answer.sdp}};
      if (call!.isGroup) body.addAll({'from': _me, 'to': from});
      await _send('answer', body);
    });
    ch.onBroadcast(event: 'answer', callback: (m) async {
      final p = _payloadOf(m);
      if (!_forMe(p)) return;
      final peer = peers[_fromOf(p)];
      if (peer?.pc == null) return;
      final sdp = Map<String, dynamic>.from(p['sdp']);
      await peer!.pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
      peer.remoteSet = true;
      await _drain(peer);
    });
    ch.onBroadcast(event: 'ice', callback: (m) async {
      final p = _payloadOf(m);
      if (!_forMe(p)) return;
      final cand = Map<String, dynamic>.from(p['candidate'] ?? {});
      final ice = RTCIceCandidate(cand['candidate'], cand['sdpMid'], (cand['sdpMLineIndex'] as num?)?.toInt());
      final peer = peers[_fromOf(p)];
      if (peer == null || peer.pc == null || !peer.remoteSet) {
        // Arrived before the offer — keep it for later.
        final holder = peers.putIfAbsent(_fromOf(p), () => CallPeer(_fromOf(p), '', null));
        holder.pendingIce.add(ice);
        return;
      }
      try {
        await peer.pc!.addCandidate(ice);
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------- actions
  Future<void> startCall({
    required String chatId,
    required String peerUserId,
    required String peerName,
    String? peerAvatar,
    required String kind,
  }) async {
    if (_me == null) return;
    if (call != null) return _fail('Already in a call');
    final callId = _uuid();
    call = ActiveCall(
      callId: callId,
      kind: kind,
      chatId: chatId,
      isGroup: false,
      isCaller: true,
      title: peerName,
      avatar: peerAvatar,
      peerUserId: peerUserId,
      status: CallStatus.outgoing,
    );
    _outcome = '';
    minimized = false;
    notifyListeners();
    try {
      await _getMedia(kind);
      await _subscribeCall('call:$callId');
      await _peer(peerUserId, name: peerName, avatar: peerAvatar);
      _ringer.startOutgoing();
      await _sendTo('user:$peerUserId', 'call-invite', {
        'callId': callId,
        'fromUserId': _me,
        'fromName': auth.profile?.displayName ?? auth.profile?.username ?? 'Someone',
        'fromAvatar': auth.profile?.avatarUrl,
        'kind': kind,
        'chatId': chatId,
      });
      _wakePhone(peerUserId, callId, chatId, kind);
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (call?.status == CallStatus.outgoing) hangup();
      });
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', ''));
      _cleanup();
    }
  }

  /// Ask the website's server to ring the other person's phone if their app is closed.
  Future<void> _wakePhone(String callee, String callId, String chatId, String kind, {String type = 'call'}) async {
    final token = db.auth.currentSession?.accessToken;
    if (token == null || chatId.isEmpty) return;
    try {
      await http.post(Uri.parse('${AppConfig.siteUrl}/api/public/v1/push/call'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({'callee_id': callee, 'call_id': callId, 'chat_id': chatId, 'kind': kind == 'video' ? 'video' : 'audio', 'type': type}));
    } catch (_) {}
  }

  Future<void> startGroupCall({
    required String chatId,
    required String title,
    required List<GroupInvitee> members,
    required String kind,
  }) async {
    final me = _me;
    if (me == null) return;
    if (call != null) return _fail('Already in a call');
    final others = members.where((m) => m.userId != me).toList();
    if (others.isEmpty) return _fail('Nobody else in this group yet');
    final callId = _uuid();
    call = ActiveCall(
      callId: callId,
      kind: kind,
      chatId: chatId,
      isGroup: true,
      isCaller: true,
      title: title,
      status: CallStatus.outgoing,
    );
    _outcome = '';
    minimized = false;
    notifyListeners();
    try {
      await _getMedia(kind);
      await _subscribeCall('gcall:$callId');
      _joinedAt = DateTime.now().millisecondsSinceEpoch;
      _ringer.startOutgoing();
      final invite = {
        'callId': callId,
        'fromUserId': me,
        'fromName': auth.profile?.displayName ?? 'Someone',
        'fromAvatar': auth.profile?.avatarUrl,
        'groupTitle': title,
        'kind': kind,
        'chatId': chatId,
      };
      await Future.wait(others.map((m) => _sendTo('user:${m.userId}', 'group-call-invite', invite)));
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (call?.status == CallStatus.outgoing) hangup();
      });
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', ''));
      _cleanup();
    }
  }

  Future<void> accept() async {
    final c = call;
    if (c == null || c.isCaller || c.status != CallStatus.incoming) return;
    _ringer.stop();
    _ringTimeout?.cancel();
    c.status = CallStatus.connecting;
    notifyListeners();
    _notifyOtherDevices(c.callId, 'accepted');
    try {
      await _getMedia(c.kind);
      if (c.isGroup) {
        await _subscribeCall('gcall:${c.callId}');
        _joinedAt = DateTime.now().millisecondsSinceEpoch;
        await _send('join', {
          'callId': c.callId,
          'userId': _me,
          'name': auth.profile?.displayName,
          'avatar': auth.profile?.avatarUrl,
          'joinedAt': _joinedAt,
        });
      } else {
        await _subscribeCall('call:${c.callId}');
        await _peer(c.peerUserId!, name: c.title, avatar: c.avatar);
        await _send('accept', {'callId': c.callId});
      }
      // Watchdog: give up if nothing connects within 30s.
      _ringTimeout = Timer(const Duration(seconds: 30), () {
        if (call != null && call!.status != CallStatus.active) _cleanup(toast: 'Could not connect');
      });
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', ''));
      _cleanup();
    }
  }

  Future<void> reject() async {
    final c = call;
    if (c == null) return;
    _outcome = 'declined';
    _notifyOtherDevices(c.callId, 'rejected');
    final topic = c.isGroup ? 'gcall:${c.callId}' : 'call:${c.callId}';
    unawaited(_sendTo(topic, 'reject', {'callId': c.callId, 'userId': _me}));
    _cleanup();
  }

  Future<void> hangup() async {
    final c = call;
    if (c == null) return;
    if (c.status == CallStatus.incoming) return reject();
    if (c.isGroup) {
      await _send('leave', {'callId': c.callId, 'userId': _me});
    } else {
      await _send('hangup', {'callId': c.callId});
      if (c.isCaller && c.status != CallStatus.active && c.peerUserId != null) {
        _wakePhone(c.peerUserId!, c.callId, c.chatId, c.kind, type: 'call_cancel');
      }
    }
    _cleanup();
  }

  void _notifyOtherDevices(String callId, String action) {
    final me = _me;
    if (me == null || _inbox == null) return;
    _inbox!.sendBroadcastMessage(event: 'answered-elsewhere', payload: {'v': 1, 'callId': callId, 'action': action});
  }

  // ---------------------------------------------------------------- controls
  void toggleMute() {
    muted = !muted;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final t = localStream?.getVideoTracks();
    if (t != null && t.isNotEmpty) await Helper.switchCamera(t.first);
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await Helper.setSpeakerphoneOn(speakerOn);
    notifyListeners();
  }

  void setMinimized(bool v) {
    minimized = v;
    notifyListeners();
  }

  Future<List<RTCRtpSender>> _videoSenders() async {
    final out = <RTCRtpSender>[];
    for (final p in peers.values) {
      final pc = p.pc;
      if (pc == null) continue;
      for (final tr in await pc.getTransceivers()) {
        if (tr.receiver.track?.kind == 'video' || tr.sender.track?.kind == 'video') {
          out.add(tr.sender);
          break;
        }
      }
    }
    return out;
  }

  /// Screen sharing: swaps the outgoing camera picture for the screen without
  /// reconnecting (website does the same), and swaps back on stop.
  /// [desktopSourceId] comes from the source picker on Windows/macOS.
  Future<void> startScreenShare({String? desktopSourceId}) async {
    if (call == null || sharing) return;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Android 10+ requires a visible foreground service while capturing.
        final ok = await FlutterBackground.initialize(
          androidConfig: const FlutterBackgroundAndroidConfig(
            notificationTitle: 'TR MATRIX',
            notificationText: 'Sharing your screen',
            notificationImportance: AndroidNotificationImportance.normal,
          ),
        );
        if (ok) await FlutterBackground.enableBackgroundExecution();
      }
      final MediaStream screen = await navigator.mediaDevices.getDisplayMedia(desktopSourceId != null
          ? {
              'video': {'deviceId': {'exact': desktopSourceId}, 'mandatory': {'frameRate': 15.0}},
              'audio': false,
            }
          : {'video': true, 'audio': false});
      final track = screen.getVideoTracks().first;
      final cams = localStream?.getVideoTracks() ?? [];
      _camTrack = cams.isNotEmpty ? cams.first : null;
      for (final s in await _videoSenders()) {
        await s.replaceTrack(track);
      }
      track.onEnded = () => stopScreenShare();
      localRenderer.srcObject = screen;
      _screen = screen;
      sharing = true;
      notifyListeners();
    } catch (e) {
      _fail('Screen sharing was cancelled or is not allowed.');
    }
  }

  MediaStream? _screen;

  Future<void> stopScreenShare() async {
    if (!sharing) return;
    for (final s in await _videoSenders()) {
      await s.replaceTrack(_camTrack);
    }
    for (final t in _screen?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    _screen = null;
    localRenderer.srcObject = localStream;
    sharing = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterBackground.disableBackgroundExecution();
      } catch (_) {}
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- teardown
  void _fail(String msg) {
    error = msg;
    notifyListeners();
  }

  void clearError() => error = null;

  void _closePeer(String uid) {
    final p = peers.remove(uid);
    p?.pc?.close();
    if (p?.rendererReady == true) {
      p!.renderer.srcObject = null;
      p.renderer.dispose();
    }
  }

  void _cleanup({String? toast}) {
    final c = call;
    if (c == null) return;
    _ringer.stop();
    _ringTimeout?.cancel();
    if (sharing) unawaited(stopScreenShare());
    _writeLog(c);
    for (final id in peers.keys.toList()) {
      _closePeer(id);
    }
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    localStream?.dispose();
    localStream = null;
    if (_localReady) localRenderer.srcObject = null;
    if (_callCh != null) db.removeChannel(_callCh!);
    _callCh = null;
    _joinedAt = 0;
    muted = cameraOff = sharing = minimized = false;
    call = null;
    if (toast != null) error = toast;
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void _writeLog(ActiveCall c) {
    final me = _me;
    if (me == null || _outcome == 'answered_elsewhere') return;
    final wasActive = c.activeAt != null;
    final outcome = _outcome.isNotEmpty ? _outcome : (wasActive ? 'completed' : (c.isCaller ? 'cancelled' : 'missed'));
    final peerId = c.peerUserId ?? (peers.keys.isNotEmpty ? peers.keys.first : null);
    final row = {
      'user_id': me,
      'call_id': c.callId,
      'chat_id': c.chatId,
      'peer_user_id': peerId ?? me,
      'peer_name': c.isGroup ? '${c.title} (group)' : c.title,
      'kind': c.kind,
      'direction': c.isCaller ? 'outgoing' : 'incoming',
      'outcome': outcome,
      'started_at': c.startedAt.toUtc().toIso8601String(),
      'duration_sec': wasActive ? DateTime.now().difference(c.activeAt!).inSeconds : 0,
    };
    db.from('call_logs').upsert(row, onConflict: 'user_id,call_id').then((_) {}, onError: (e) => debugPrint('[call] log failed: $e'));
  }

  Future<List<Map<String, dynamic>>> history() async {
    final me = _me;
    if (me == null) return [];
    final rows = await db.from('call_logs').select().eq('user_id', me).order('started_at', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    _ringer.dispose();
    super.dispose();
  }
}
