import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _kDeviceId = 'tr-matrix.device-id';
const _kRegKey = 'tr-matrix.device-registered';

String _browserLabel() {
  // minimal UA sniff — matches web deviceName()
  return 'TR MATRIX app';
}

Future<String> localDeviceId() async {
  final p = await SharedPreferences.getInstance();
  var id = p.getString(_kDeviceId);
  if (id == null || id.isEmpty) {
    id = const Uuid().v4();
    await p.setString(_kDeviceId, id);
  }
  return id;
}

Future<String> webToken() async => 'web:${await localDeviceId()}';
String devicesChannelName(String userId) => 'devices:$userId';

class DeviceRow {
  final String id, token, platform;
  final String? deviceName;
  final DateTime lastSeenAt;
  const DeviceRow({
    required this.id,
    required this.token,
    required this.platform,
    this.deviceName,
    required this.lastSeenAt,
  });
  factory DeviceRow.fromJson(Map<String, dynamic> j) => DeviceRow(
        id: j['id'] as String,
        token: j['token'] as String,
        platform: j['platform'] as String,
        deviceName: j['device_name'] as String?,
        lastSeenAt: DateTime.tryParse(j['last_seen_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

Future<String> registerThisDevice(SupabaseClient db, String userId) async {
  final token = await webToken();
  try {
    final existing = await db
        .from('device_tokens')
        .select('id')
        .eq('token', token)
        .maybeSingle();
    final prefs = await SharedPreferences.getInstance();
    if (existing == null && prefs.getString(_kRegKey) == userId)
      return 'revoked';
    await db.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': 'web',
      'device_name': _browserLabel(),
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
    // upsert returns data/error via exception; if no throw, success
    await prefs.setString(_kRegKey, userId);
    return 'ok';
  } catch (_) {
    return 'unavailable';
  }
}

Future<void> forgetRegistration() async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_kRegKey);
}

Future<List<DeviceRow>> listDevices(SupabaseClient db) async {
  final rows = List<Map<String, dynamic>>.from(
    await db
        .from('device_tokens')
        .select('id, token, platform, device_name, last_seen_at')
        .order('last_seen_at', ascending: false),
  );
  return rows.map(DeviceRow.fromJson).toList();
}

Future<void> removeDevice(
  SupabaseClient db,
  String userId,
  DeviceRow row,
) async {
  await db.from('device_tokens').delete().eq('id', row.id);
  final ch = db.channel(
    devicesChannelName(userId),
    opts: RealtimeChannelConfig(self: false),
  );
  final done = Completer<void>();
  ch.subscribe((s, _) async {
    if (s == RealtimeSubscribeStatus.subscribed) {
      try {
        await ch.sendBroadcastMessage(
          event: 'remote-logout',
          payload: {'v': 1, 'token': row.token},
        );
      } catch (_) {}
      done.complete();
    }
  });
  await done.future.timeout(const Duration(seconds: 4), onTimeout: () {});
  try {
    await db.removeChannel(ch);
  } catch (_) {}
}
