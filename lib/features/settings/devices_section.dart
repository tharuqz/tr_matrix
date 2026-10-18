import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../data/devices_repository.dart';
import '../../widgets/common.dart';

/// Port of `devices-section.tsx` — lists device_tokens, sign out others.
class DevicesSection extends StatefulWidget {
  const DevicesSection({super.key});
  @override
  State<DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<DevicesSection> {
  List<DeviceRow>? _rows;
  String? _mine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _mine = await webToken();
    } catch (_) {}
    try {
      final r = await listDevices(Supabase.instance.client);
      if (mounted) setState(() => _rows = r);
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  IconData _icon(String p) => switch (p) {
        'android' => Icons.smartphone_rounded,
        'ios' => Icons.phone_iphone_rounded,
        'windows' => Icons.desktop_windows_rounded,
        'web' => Icons.language_rounded,
        _ => Icons.devices_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    if (_rows == null)
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Loading devices…', style: TRText.body(13, c.text2)),
      );
    if (_rows!.isEmpty)
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No devices yet.', style: TRText.body(13, c.text2)),
      );
    return Column(
      children: [
        for (final d in _rows!)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(_icon(d.platform), size: 18, color: c.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d.deviceName ?? d.platform}${d.token == _mine ? ' · This device' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TRText.body(13, c.text1, w: FontWeight.w600),
                      ),
                      Text(
                        '${d.platform} · ${d.lastSeenAt.toLocal().toString().substring(0, 16)}',
                        style: TRText.body(11, c.text3),
                      ),
                    ],
                  ),
                ),
                if (d.token != _mine)
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(
                            'Sign out ${d.deviceName ?? 'this device'}?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      try {
                        await removeDevice(
                          Supabase.instance.client,
                          Supabase.instance.client.auth.currentUser!.id,
                          d,
                        );
                        if (mounted) showToast(context, 'Device signed out');
                        _load();
                      } catch (e) {
                        if (mounted)
                          showToast(context, e.toString(), error: true);
                      }
                    },
                    child: const Text('Sign out'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
