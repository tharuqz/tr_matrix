import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_scope.dart';
import '../../core/fancy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';

/// Security (admin only). Port of routes/app.admin.tsx: site controls, members, reports.
/// Every action is checked again by the server — the app only hides the screen.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final db = Supabase.instance.client;
  Map<String, dynamic> _settings = {};
  List<Map<String, dynamic>>? _users;
  List<Map<String, dynamic>>? _reports;
  String _reportFilter = 'open';
  final _search = TextEditingController();
  int _page = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSettings(), _loadUsers(), _loadReports()]);
  }

  Future<void> _loadSettings() async {
    try {
      final rows = await db.from('app_settings').select('key, value');
      if (mounted) setState(() => _settings = {for (final r in rows) r['key'] as String: r['value']});
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _loadUsers() async {
    try {
      final rows = await db.rpc('admin_list_users');
      if (mounted) setState(() => _users = List<Map<String, dynamic>>.from(rows ?? []));
    } catch (e) {
      if (mounted) setState(() => _users = []);
      _toast(e);
    }
  }

  Future<void> _loadReports() async {
    try {
      var q = db.from('reports').select('id, reason, status, created_at, reporter_id, target_user_id, message_id');
      if (_reportFilter == 'open') q = q.eq('status', 'open');
      final rows = await q.order('created_at', ascending: false).limit(50);
      if (mounted) setState(() => _reports = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) setState(() => _reports = []);
    }
  }

  void _toast(Object e) {
    if (!mounted) return;
    showToast(context, e is PostgrestException ? e.message : '$e', error: true);
  }

  Future<void> _setFlag(String key, bool value) async {
    setState(() => _busy = true);
    try {
      await db.from('app_settings').upsert({'key': key, 'value': value, 'updated_at': DateTime.now().toUtc().toIso8601String()});
      await _loadSettings();
      if (mounted) showToast(context, 'Setting updated');
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await db.rpc('admin_set_account_status', params: {'_user_id': id, '_status': status});
      await _loadUsers();
      if (mounted) showToast(context, 'User $status');
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('This permanently deletes @${u['username']} and frees the username. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.rpc('admin_delete_user', params: {'_user_id': u['id']});
      await _loadUsers();
      if (mounted) showToast(context, 'Account deleted — username is free again');
    } catch (e) {
      _toast(e);
    }
  }

  Future<void> _setReport(String id, String status) async {
    try {
      await db.from('reports').update({'status': status}).eq('id', id);
      await _loadReports();
    } catch (e) {
      _toast(e);
    }
  }

  Widget _section(String title, String sub, List<Widget> children, {Widget? trailing}) {
    final c = context.tr;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface1, borderRadius: BorderRadius.circular(TRRadius.x3l), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TRText.display(17, c.text1)),
              Text(sub, style: TRText.body(12, c.text3)),
            ]),
          ),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    if (!AppScope.of(context).auth.isAdmin) {
      return const EmptyState(icon: Icons.lock_outline_rounded, title: 'Admins only');
    }
    final me = AppScope.of(context).auth.user?.id;
    final term = _search.text.trim().replaceFirst('@', '').toLowerCase();
    final filtered = (_users ?? []).where((u) => '${plainName(u['display_name'] ?? '')} ${u['username']}'.toLowerCase().contains(term)).toList();
    final pages = (filtered.length / 25).ceil().clamp(1, 9999);
    final page = _page.clamp(0, pages - 1);
    final visible = filtered.skip(page * 25).take(25).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + mobileBarClearance(context)), children: [
          Row(children: [
            Icon(Icons.shield_rounded, color: context.accent, size: 28),
            const SizedBox(width: 10),
            Text('Security', style: TRText.display(24, c.text1)),
          ]),
          const SizedBox(height: 16),
          _section('Site controls', 'Site-wide flags applied to every user.', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Maintenance mode'),
              subtitle: const Text('Show a locked screen to non-admin users.'),
              value: _settings['maintenance_mode'] == true,
              onChanged: _busy ? null : (v) => _setFlag('maintenance_mode', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Community posting lock'),
              subtitle: const Text('Only admins can post in the Hives feed.'),
              value: _settings['announcement_lock'] != false,
              onChanged: _busy ? null : (v) => _setFlag('announcement_lock', v),
            ),
          ]),
          _section(
            'Members',
            '${_users?.length ?? 0} registered users.',
            [
              TRTextField(controller: _search, hint: 'Search name or @username', icon: Icons.search_rounded, onChanged: (_) => setState(() => _page = 0)),
              const SizedBox(height: 8),
              if (_users == null) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
              for (final u in visible)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: TRAvatar(name: plainName(u['display_name'] ?? '?'), url: u['avatar_url'], size: 40),
                  title: FancyText(u['display_name'] ?? '', style: TRText.body(14, c.text1, w: FontWeight.w600), maxLines: 1),
                  subtitle: Text('@${u['username']} · ${u['account_status'] ?? 'active'}${u['is_admin'] == true ? ' · admin' : ''}', style: TRText.body(12, c.text3)),
                  trailing: u['id'] == me
                      ? Text('You', style: TRText.body(12, c.text3))
                      : PopupMenuButton<String>(
                          onSelected: (v) => v == 'delete' ? _delete(u) : _setStatus(u['id'], v),
                          itemBuilder: (_) => [
                            if (u['account_status'] != 'active') const PopupMenuItem(value: 'active', child: Text('Activate')),
                            if (u['account_status'] != 'suspended') const PopupMenuItem(value: 'suspended', child: Text('Suspend')),
                            if (u['account_status'] != 'banned') const PopupMenuItem(value: 'banned', child: Text('Ban')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete account')),
                          ],
                        ),
                ),
              if (pages > 1)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: page > 0 ? () => setState(() => _page = page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                  Text('${page + 1} / $pages'),
                  IconButton(onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                ]),
            ],
            trailing: TRIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh', onPressed: _loadUsers),
          ),
          _section(
            'Flagged reports',
            'Messages and people reported by members.',
            [
              Row(children: [
                ChoiceChip(label: const Text('Open'), selected: _reportFilter == 'open', onSelected: (_) {
                  setState(() => _reportFilter = 'open');
                  _loadReports();
                }),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('All'), selected: _reportFilter == 'all', onSelected: (_) {
                  setState(() => _reportFilter = 'all');
                  _loadReports();
                }),
              ]),
              const SizedBox(height: 8),
              if (_reports == null) const Center(child: CircularProgressIndicator()),
              if (_reports != null && _reports!.isEmpty) Text('No reports.', style: TRText.body(13, c.text3)),
              for (final r in _reports ?? <Map<String, dynamic>>[])
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(TRRadius.xl)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['reason'] ?? '(no reason)', style: TRText.body(14, c.text1)),
                    const SizedBox(height: 4),
                    Text(
                      '${r['status']} · ${DateFormat('MMM d, HH:mm').format(DateTime.parse(r['created_at']).toLocal())}${r['target_user_id'] != null ? ' · user ${(r['target_user_id'] as String).substring(0, 6)}' : ''}',
                      style: TRText.body(12, c.text3),
                    ),
                    if (r['status'] == 'open')
                      Row(children: [
                        TextButton(onPressed: () => _setReport(r['id'], 'reviewed'), child: const Text('Mark reviewed')),
                        TextButton(onPressed: () => _setReport(r['id'], 'dismissed'), child: const Text('Dismiss')),
                      ]),
                  ]),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}
