import '../../core/desktop_menu.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Port of `disappearing-menu.tsx`.
///
/// Reads `chats.disappear_after_sec`, calls `rpc('set_disappearing')`.
const _options = [
  (0, 'Off'),
  (3600, '1 hour'),
  (86400, '24 hours'),
  (604800, '7 days'),
  (7776000, '90 days'),
];

class DisappearingMenu extends StatefulWidget {
  final String chatId;
  final bool labeled;
  const DisappearingMenu({
    super.key,
    required this.chatId,
    this.labeled = false,
  });
  @override
  State<DisappearingMenu> createState() => _DisappearingMenuState();
}

class _DisappearingMenuState extends State<DisappearingMenu> {
  int _secs = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client
          .from('chats')
          .select('disappear_after_sec')
          .eq('id', widget.chatId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _secs = (row?['disappear_after_sec'] as int?) ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _change(int n) async {
    final prev = _secs;
    setState(() => _secs = n);
    try {
      await Supabase.instance.client.rpc(
        'set_disappearing',
        params: {'_chat_id': widget.chatId, '_secs': n},
      );
      // supabase_flutter rpc returns data not error; catch handles failure
      if (!mounted) return;
      final label =
          _options.firstWhere((o) => o.$1 == n, orElse: () => (0, 'Off')).$2;
      showToast(
        context,
        n == 0
            ? 'Disappearing messages off'
            : 'New messages disappear after $label',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _secs = prev);
      showToast(
        context,
        'Run the latest database update to use disappearing messages.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final label =
        _options.firstWhere((o) => o.$1 == _secs, orElse: () => (0, 'Off')).$2;
    if (widget.labeled) {
      return ListTile(
        leading: Icon(Icons.timer_outlined, color: c.text2),
        title: const Text('Disappearing messages'),
        subtitle: Text(label, style: TRText.body(12, c.text2)),
        trailing: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: () => _sheet(context),
      );
    }
    return IconButton(
      tooltip: 'Disappearing messages',
      icon: Icon(Icons.timer_outlined, color: c.text2),
      onPressed: () => _sheet(context),
    );
  }

  void _sheet(BuildContext context) {
    final c = context.tr;
    showAnchoredSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.border),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.text3.withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Disappearing messages',
                    style: TRText.body(15, c.text1, w: FontWeight.w700),
                  ),
                ),
                for (final o in _options)
                  RadioListTile<int>(
                    value: o.$1,
                    groupValue: _secs,
                    title: Text(o.$2),
                    activeColor: context.accent,
                    onChanged: (v) {
                      Navigator.pop(sheetContext);
                      if (v != null) _change(v);
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
