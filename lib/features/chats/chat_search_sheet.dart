import '../../core/desktop_menu.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/fancy.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

class SharedRow {
  final String id;
  final String? content, mediaUrl, mediaType, mediaName;
  final DateTime createdAt;
  const SharedRow({
    required this.id,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.mediaName,
    required this.createdAt,
  });
  factory SharedRow.fromJson(Map<String, dynamic> j) => SharedRow(
        id: j['id'] as String,
        content: j['content'] as String?,
        mediaUrl: j['media_url'] as String?,
        mediaType: j['media_type'] as String?,
        mediaName: j['media_name'] as String?,
        createdAt:
            DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

String? sharedKind(SharedRow r) {
  if (r.mediaUrl == null || r.mediaUrl!.isEmpty) return null;
  if (RegExp(r'^(image|video)/').hasMatch(r.mediaType ?? '')) return 'media';
  return 'docs';
}

List<String> sharedLinks(String? raw) {
  final plain = raw == null || raw.isEmpty ? '' : decodeFancy(raw).text;
  final re = RegExp(r'https?://[^\\s<>]+', caseSensitive: false);
  final out = <String>{};
  for (final m in re.allMatches(plain))
    out.add(m.group(0)!.replaceAll(RegExp(r'[),.!?;:]+\$'), ''));
  return out.toList();
}

String stripFancyPreview(String? raw) =>
    raw == null || raw.isEmpty ? '' : decodeFancy(raw).text;

class ChatSearchSheet extends StatefulWidget {
  final String chatId;
  final void Function(String messageId) onJump;
  final int initialTab;
  const ChatSearchSheet({
    super.key,
    required this.chatId,
    required this.onJump,
    this.initialTab = 0,
  });
  static Future<void> show(
    BuildContext c,
    String chatId,
    void Function(String) onJump, {
    int initialTab = 0,
  }) =>
      showAnchoredSheet(
        large: true,
        context: c,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.5,
          maxChildSize: 0.96,
          expand: false,
          builder: (_, __) => ChatSearchSheet(
            chatId: chatId,
            onJump: onJump,
            initialTab: initialTab,
          ),
        ),
      );
  @override
  State<ChatSearchSheet> createState() => _ChatSearchSheetState();
}

class _ChatSearchSheetState extends State<ChatSearchSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _q = TextEditingController();
  List<SharedRow> _results = [], _shared = [];
  bool _busy = false, _sharedBusy = false;
  String? _error;
  int _page = 0;
  bool _hasMore = false;
  Timer? _debounce;
  static const _select =
      'id, content, media_url, media_type, media_name, created_at';
  static const _pageSize = 60;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {
        _shared = [];
        _page = 0;
        _hasMore = false;
        _error = null;
      });
      if (_tabs.index != 0) _loadShared();
    });
    if (_tabs.index != 0) _loadShared();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadShared() async {
    final tab = _tabs.index;
    if (tab == 0) return;
    setState(() => _sharedBusy = true);
    try {
      final db = Supabase.instance.client;
      final rows = List<Map<String, dynamic>>.from(
        await db
            .from('messages')
            .select(_select)
            .eq('chat_id', widget.chatId)
            .eq('deleted', false)
            .order('created_at', ascending: false)
            .range(_page * _pageSize, (_page + 1) * _pageSize),
      );
      var f = rows.map(SharedRow.fromJson).toList();
      if (tab == 1) f = f.where((r) => sharedKind(r) == 'media').toList();
      if (tab == 2)
        f = f.where((r) => sharedLinks(r.content).isNotEmpty).toList();
      if (tab == 3) f = f.where((r) => sharedKind(r) == 'docs').toList();
      if (!mounted) return;
      setState(() {
        _shared = _page == 0
            ? f.take(_pageSize).toList()
            : [..._shared, ...f.take(_pageSize)];
        _hasMore = rows.length >= _pageSize;
        _sharedBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sharedBusy = false;
        _error = "Couldn\'t load. Try again.";
      });
    }
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final q = v.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _results = []);
        return;
      }
      setState(() => _busy = true);
      try {
        final rows = List<Map<String, dynamic>>.from(
          await Supabase.instance.client
              .from('messages')
              .select(_select)
              .eq('chat_id', widget.chatId)
              .eq('deleted', false)
              .ilike('content', '%\$q%')
              .order('created_at', ascending: false)
              .limit(40),
        );
        if (!mounted) return;
        setState(() => _results = rows.map(SharedRow.fromJson).toList());
      } catch (_) {
        if (mounted) setState(() => _error = "Couldn\'t search. Try again.");
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: c.border),
      ),
      child: Column(
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
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _tabs.index == 0
                        ? 'Search messages'
                        : 'Media, links & docs',
                    style: TRText.body(16, c.text1, w: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: c.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: context.accent,
            unselectedLabelColor: c.text2,
            indicatorColor: context.accent,
            tabs: const [
              Tab(icon: Icon(Icons.search_rounded, size: 18), text: 'Search'),
              Tab(icon: Icon(Icons.image_outlined, size: 18), text: 'Media'),
              Tab(icon: Icon(Icons.link_rounded, size: 18), text: 'Links'),
              Tab(
                icon: Icon(Icons.description_outlined, size: 18),
                text: 'Docs',
              ),
            ],
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TRText.body(13, c.danger)),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _SearchTab(
                  q: _q,
                  onChanged: _onQuery,
                  busy: _busy,
                  results: _results,
                  onJump: (id) {
                    Navigator.pop(context);
                    widget.onJump(id);
                  },
                ),
                _SharedTab(
                  rows: _shared,
                  busy: _sharedBusy,
                  hasMore: _hasMore,
                  kind: 'media',
                  onMore: () {
                    setState(() => _page++);
                    _loadShared();
                  },
                ),
                _SharedTab(
                  rows: _shared,
                  busy: _sharedBusy,
                  hasMore: _hasMore,
                  kind: 'links',
                  onMore: () {
                    setState(() => _page++);
                    _loadShared();
                  },
                ),
                _SharedTab(
                  rows: _shared,
                  busy: _sharedBusy,
                  hasMore: _hasMore,
                  kind: 'docs',
                  onMore: () {
                    setState(() => _page++);
                    _loadShared();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTab extends StatelessWidget {
  final TextEditingController q;
  final ValueChanged<String> onChanged;
  final bool busy;
  final List<SharedRow> results;
  final ValueChanged<String> onJump;
  const _SearchTab({
    required this.q,
    required this.onChanged,
    required this.busy,
    required this.results,
    required this.onJump,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TRTextField(
            controller: q,
            hint: 'Search this chat...',
            icon: Icons.search_rounded,
            onChanged: onChanged,
          ),
        ),
        Expanded(
          child: busy
              ? Center(
                  child: Text('Searching...', style: TRText.body(13, c.text2)),
                )
              : results.isEmpty && q.text.trim().length >= 2
                  ? Center(
                      child: Text(
                        'No messages found.',
                        style: TRText.body(13, c.text2),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final r = results[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onJump(r.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: c.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '\${r.createdAt.day.toString().padLeft(2,"0")} ${_mmm(r.createdAt.month)} \${r.createdAt.hour.toString().padLeft(2,"0")}:\${r.createdAt.minute.toString().padLeft(2,"0")}',
                                  style: TRText.body(11, c.text3),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  stripFancyPreview(r.content),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TRText.body(13, c.text1),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _SharedTab extends StatelessWidget {
  final List<SharedRow> rows;
  final bool busy, hasMore;
  final String kind;
  final VoidCallback onMore;
  const _SharedTab({
    required this.rows,
    required this.busy,
    required this.hasMore,
    required this.kind,
    required this.onMore,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    if (!busy && rows.isEmpty)
      return Center(
        child: Text(
          kind == 'media'
              ? 'No photos or videos yet.'
              : kind == 'links'
                  ? 'No links yet.'
                  : 'No documents yet.',
          style: TRText.body(13, c.text2),
        ),
      );
    return Column(
      children: [
        Expanded(
          child: kind == 'media'
              ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _MediaThumb(row: rows[i]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    if (kind == 'links') {
                      final links = sharedLinks(r.content);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surface2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final u in links)
                              Row(
                                children: [
                                  Icon(
                                    Icons.link_rounded,
                                    size: 16,
                                    color: context.accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      u,
                                      style: TRText.body(13, context.accent),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }
                    return _MediaThumb(row: r);
                  },
                ),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Loading...', style: TRText.body(13, c.text2)),
          ),
        if (hasMore && !busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onMore,
                child: const Text('Load more'),
              ),
            ),
          ),
      ],
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final SharedRow row;
  const _MediaThumb({required this.row});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final isDoc = sharedKind(row) == 'docs';
    return Container(
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: isDoc
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.description_rounded, color: c.text2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.mediaName ?? 'Document',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TRText.body(13, c.text1),
                        ),
                        Text(
                          '\${row.createdAt.day}/\${row.createdAt.month}/\${row.createdAt.year}',
                          style: TRText.body(11, c.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1,
                child: ColoredBox(
                  color: c.surface3,
                  child: Icon(
                    (row.mediaType ?? '').startsWith('video/')
                        ? Icons.movie_rounded
                        : Icons.image_rounded,
                    color: c.text3,
                  ),
                ),
              ),
            ),
    );
  }
}

String _mmm(int m) => const [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][m];
