import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';

/// Calls tab — call history (same `call_logs` table as the website) with call-back buttons.
class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _initialized = false;
  String _filter = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _future = AppScope.of(context).calls.history();
  }

  Future<void> _reload() async {
    setState(() => _future = AppScope.of(context).calls.history());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final calls = AppScope.of(context).calls;
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Calls', style: TRText.display(28, c.text1)),
                    ),
                    TRIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onPressed: _reload,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MatrixTabs(
                  labels: const ['All', 'Missed', 'Incoming', 'Outgoing'],
                  selected: const [
                    'all',
                    'missed',
                    'incoming',
                    'outgoing',
                  ].indexOf(_filter),
                  onChanged: (i) => setState(
                    () => _filter = const [
                      'all',
                      'missed',
                      'incoming',
                      'outgoing',
                    ][i],
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done)
                      return const Center(child: CircularProgressIndicator());
                    if (snap.hasError) {
                      return EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load calls',
                        subtitle: '${snap.error}',
                      );
                    }
                    var rows = snap.data ?? [];
                    rows = rows.where((r) {
                      if (_filter == 'all') return true;
                      if (_filter == 'missed') return r['outcome'] == 'missed';
                      return r['direction'] == _filter;
                    }).toList();
                    if (rows.isEmpty) {
                      return const EmptyState(
                        icon: Icons.call_outlined,
                        title: 'No calls yet',
                        subtitle: 'Start a call from any chat.',
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          12,
                          12,
                          24 + mobileBarClearance(context),
                        ),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final missed = r['outcome'] == 'missed';
                          final out = r['direction'] == 'outgoing';
                          final video = r['kind'] == 'video';
                          final group = (r['peer_name'] as String? ?? '')
                              .endsWith('(group)');
                          final when = DateTime.tryParse(
                            r['started_at'] ?? '',
                          )?.toLocal();
                          final dur = (r['duration_sec'] as num?)?.toInt() ?? 0;
                          final sub = [
                            out ? 'Outgoing' : 'Incoming',
                            if (r['outcome'] != 'completed')
                              '${r['outcome']}'.replaceAll('_', ' '),
                            if (dur > 0) '${dur ~/ 60}m ${dur % 60}s',
                            if (when != null)
                              DateFormat('MMM d, HH:mm').format(when),
                          ].join(' · ');
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: c.border),
                              ),
                            ),
                            child: Row(
                              children: [
                                TRAvatar(name: r['peer_name'] ?? '?', size: 44),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r['peer_name'] ?? 'Unknown',
                                        style: TRText.body(
                                          15,
                                          missed ? c.danger : c.text1,
                                          w: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            out
                                                ? Icons.call_made_rounded
                                                : (missed
                                                    ? Icons.call_missed_rounded
                                                    : Icons
                                                        .call_received_rounded),
                                            size: 14,
                                            color: missed ? c.danger : c.text3,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              sub,
                                              style: TRText.body(12, c.text3),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!group)
                                  TRIconButton(
                                    icon: video
                                        ? Icons.videocam_outlined
                                        : Icons.call_outlined,
                                    tooltip: 'Call back',
                                    onPressed: () => calls.startCall(
                                      chatId: r['chat_id'] ?? '',
                                      peerUserId: r['peer_user_id'],
                                      peerName: r['peer_name'] ?? 'Contact',
                                      kind: video ? 'video' : 'voice',
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
