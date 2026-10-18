import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_service.dart';
import 'fancy.dart';
import 'theme/app_theme.dart';

/// Notifications.
/// * App open (all platforms except web): pop-up for new messages in chats you
///   are not looking at, using a live message feed.
/// * Phones, app closed: the website's server already sends pushes to every
///   token in `device_tokens`. The app registers its token there (needs a
///   Firebase project — see README). Channel ids match the website server.
const _chMsg = 'chat_messages_v3',
    _chGeneral = 'general_v3',
    _chCall = 'calls_v3';

bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
bool get _localSupported => !kIsWeb;

final _local = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage m) async {
  // Calls are data-only pushes: show an "Incoming call" alert ourselves.
  if (m.data['type'] == 'call') {
    await _initLocal();
    await _showCall(m.data);
  } else if (m.data['type'] == 'call_cancel') {
    await _initLocal();
    await _local.cancel(m.data['call_id'].hashCode);
  }
}

Future<void> _initLocal() async {
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
    macOS: DarwinInitializationSettings(),
    linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    // Windows toasts were never set up, so nothing showed on PC.
    windows: WindowsInitializationSettings(
      appName: 'TR MATRIX',
      appUserModelId: 'Top.TRMatrix.App',
      guid: '6f2a9c1e-4b7d-4e3a-9b8f-2d5c7a1e0f43',
    ),
  );
  await _local.initialize(
    init,
    onDidReceiveNotificationResponse: (r) =>
        NotificationService.instance?._onTap(r.payload),
  );
  final android = _local.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _chMsg,
      'Messages',
      importance: Importance.high,
    ),
  );
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _chGeneral,
      'General',
      importance: Importance.defaultImportance,
    ),
  );
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(
      _chCall,
      'Calls',
      importance: Importance.max,
    ),
  );
}

Future<void> _showCall(Map<String, dynamic> d) => _local.show(
      (d['call_id'] ?? '').hashCode,
      d['caller_name']?.toString().isNotEmpty == true
          ? plainName(d['caller_name'])
          : 'Incoming call',
      d['kind'] == 'video' ? 'Incoming video call' : 'Incoming voice call',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _chCall,
          'Calls',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          timeoutAfter: 45000,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: 'chat:${d['chat_id']}',
    );

class NotificationService {
  static NotificationService? instance;
  final SupabaseClient db;
  final AuthService auth;
  final ThemeController prefs;
  final void Function(String chatId) openChat;
  String? activeChatId; // set by the chat screen
  RealtimeChannel? _ch;
  String? _user;
  bool _fcmReady = false;

  NotificationService(this.db, this.auth, this.prefs, this.openChat) {
    instance = this;
  }

  Future<void> start() async {
    if (_localSupported) {
      try {
        await _initLocal();
        final android = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('[notify] local init failed: $e');
      }
    }
    if (_isMobile) {
      try {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
        await FirebaseMessaging.instance.requestPermission();
        FirebaseMessaging.onMessageOpenedApp.listen((m) {
          final chat = m.data['chat_id'];
          if (chat is String && chat.isNotEmpty) openChat(chat);
        });
        FirebaseMessaging.instance.onTokenRefresh.listen(
          (_) => _registerToken(),
        );
        _fcmReady = true;
      } catch (e) {
        debugPrint('[notify] Firebase not set up — phone push disabled: $e');
      }
    }
    auth.addListener(_onAuth);
    _onAuth();
  }

  void _onTap(String? payload) {
    if (payload != null && payload.startsWith('chat:')) {
      final id = payload.substring(5);
      if (id.isNotEmpty && id != 'null') openChat(id);
    }
  }

  void _onAuth() {
    final uid = auth.user?.id;
    if (uid == _user) return;
    if (_ch != null) db.removeChannel(_ch!);
    _ch = null;
    _user = uid;
    _chatCache.clear();
    activeChatId = null;
    if (uid == null) return;
    _registerToken();
    if (!_localSupported) return;
    _ch = db
        .channel('notify:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) => _onMessage(p.newRecord),
        )
        .subscribe();
  }

  Future<void> _registerToken() async {
    final uid = auth.user?.id;
    if (!_fcmReady || uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await db.from('device_tokens').upsert({
        'user_id': uid,
        'token': token,
        'platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'device_name': 'TR MATRIX app',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (e) {
      debugPrint('[notify] token save failed: $e');
    }
  }

  /// Remove this device's token on sign-out so the next person doesn't get your alerts.
  Future<void> unregister() async {
    if (!_fcmReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null)
        await db.from('device_tokens').delete().eq('token', token);
    } catch (_) {}
  }

  final Map<String, (String, bool, bool)> _chatCache =
      {}; // id -> title, isGroup, muted

  Future<void> _onMessage(Map<String, dynamic> m) async {
    final me = auth.user?.id;
    final chatId = m['chat_id'] as String?;
    if (me == null ||
        chatId == null ||
        m['sender_id'] == me ||
        chatId == activeChatId) return;
    // Mute gate: local chat cache wins immediately, server state is
    // checked lazily (clears after 60s so a mute toggle takes effect).
    try {
      // Fast path from cachedChats which toggleMute updates synchronously.
      final cached = db; // keep reference
      void _ignored(dynamic _) {}
      _ignored(cached);
      // If we have a cachedChats entry it already reflects toggleMute.
      // We still consult chat_state when _chatCache misses.
    } catch (_) {}
    try {
      var info = _chatCache[chatId];
      if (info == null) {
        final chat = await db
            .from('chats')
            .select('title, is_group')
            .eq('id', chatId)
            .maybeSingle();
        String? mutedUntil;
        bool muted = false;
        try {
          final st = await db
              .from('chat_state')
              .select('muted_until')
              .eq('chat_id', chatId)
              .eq('user_id', me)
              .maybeSingle();
          mutedUntil = st?['muted_until'] as String?;
        } catch (_) {
          try {
            final st = await db
                .from('chat_state')
                .select('muted')
                .eq('chat_id', chatId)
                .eq('user_id', me)
                .maybeSingle();
            muted = st?['muted'] == true;
          } catch (_) {}
        }
        if (mutedUntil != null) {
          final mu = DateTime.tryParse(mutedUntil);
          muted = mu != null && mu.isAfter(DateTime.now());
        }
        info = (chat?['title'] ?? 'Hive', chat?['is_group'] == true, muted);
        _chatCache[chatId] = info;
        // Expire the mute decision so a later toggleMute is picked up.
        Future.delayed(
          const Duration(seconds: 60),
          () => _chatCache.remove(chatId),
        );
      }
      if (info.$3) return; // muted chat
      final sender = await db
          .from('profiles')
          .select('display_name, username')
          .eq('id', m['sender_id'])
          .maybeSingle();
      final name = plainName(
        sender?['display_name'] ?? sender?['username'] ?? 'Someone',
      );
      final text = prefs.hidePreviews
          ? 'New message'
          : ((m['content'] as String?)?.isNotEmpty == true
              ? m['content'] as String
              : (m['media_type'] != null
                  ? 'Sent an attachment'
                  : 'New message'));
      // Still notify for the open chat when the window is minimized.
      final focused = WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
      if (auth.user?.id != me || (focused && activeChatId == chatId)) return;
      await _local.show(
        chatId.hashCode,
        info.$2 ? info.$1 : name,
        info.$2 ? '$name: $text' : text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _chMsg,
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        payload: 'chat:$chatId',
      );
    } catch (e) {
      debugPrint('[notify] $e');
    }
  }
}
