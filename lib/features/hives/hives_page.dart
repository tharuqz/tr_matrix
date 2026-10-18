import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_scope.dart';
import '../../core/fancy.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/hives_repository.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../chats/groups.dart';
import '../chats/media/attachment.dart' show openImageViewer;
import '../shell/app_shell.dart';

String _err(Object e) => e is PostgrestException
    ? e.message
    : (e is StorageException
        ? e.message
        : '$e'.replaceFirst('Exception: ', ''));

/// Hives — community feed + my Hives (groups) with activities. Port of hives-page.tsx.
class HivesPage extends StatefulWidget {
  const HivesPage({super.key});
  @override
  State<HivesPage> createState() => _HivesPageState();
}

class _HivesPageState extends State<HivesPage> {
  late final HivesRepository repo = HivesRepository(Supabase.instance.client);
  final _searchCtl = TextEditingController();
  String _view = 'feed';
  HiveGroup? _selected;
  List<HiveGroup>? _groups;
  Object? _groupsError;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final g = await repo.myHives();
      if (mounted) {
        setState(() {
          _groups = g;
          _groupsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _groupsError = e);
    }
  }

  Future<void> _newHive() async {
    await showNewGroupDialog(context);
    _loadGroups();
  }

  void _showFeed() => setState(() {
        _view = 'feed';
        _selected = null;
      });

  Widget _groupList() {
    final c = context.tr;
    final q = _searchCtl.text.toLowerCase();
    final list = (_groups ?? [])
        .where((g) => g.title.toLowerCase().contains(q))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'MY HIVES',
                style: TRText.body(11, c.text3, w: FontWeight.w700),
              ),
            ),
            TRIconButton(
              icon: Icons.add_rounded,
              tooltip: 'Create Hive',
              onPressed: _newHive,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TRTextField(
          controller: _searchCtl,
          hint: 'Find a Hive',
          icon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (_groups == null && _groupsError == null)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_groupsError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Hives couldn't load.",
                    style: TRText.body(13, c.text2),
                  ),
                ),
                TextButton(onPressed: _loadGroups, child: const Text('Retry')),
              ],
            ),
          ),
        for (final g in list)
          Hoverable(
            onTap: () => setState(() {
              _selected = g;
              _view = 'groups';
            }),
            builder: (_, h) => Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: _selected?.id == g.id
                    ? context.accent.withValues(alpha: .12)
                    : (h ? c.text1.withValues(alpha: .05) : Colors.transparent),
                borderRadius: BorderRadius.circular(TRRadius.x2l),
              ),
              child: Row(
                children: [
                  TRAvatar(name: g.title, url: g.avatarUrl, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      g.title,
                      overflow: TextOverflow.ellipsis,
                      style: TRText.body(14, c.text1),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.text3, size: 18),
                ],
              ),
            ),
          ),
        if (_groups != null && list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              q.isEmpty ? 'No Hives yet' : 'No matching Hives',
              style: TRText.body(13, c.text3),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final wide = !Responsive.isMobile(context) &&
        MediaQuery.sizeOf(context).width >= 1000;
    final bottomPad = 24 + mobileBarClearance(context);
    Widget main;
    if (_view == 'feed') {
      main = const SizedBox.shrink();
    } else if (_selected != null) {
      main = ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
        children: [
          Row(
            children: [
              TRIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back to Hives',
                onPressed: () => setState(() => _selected = null),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _selected!.title,
                  style: TRText.display(18, c.text1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TRButton(
                label: 'Chat',
                icon: Icons.chat_bubble_outline_rounded,
                variant: TRButtonVariant.outline,
                onPressed: () => context.go('/app/chat/${_selected!.id}'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Activities(
            key: ValueKey(_selected!.id),
            repo: repo,
            hive: _selected!,
          ),
        ],
      );
    } else {
      main = ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
        children: [
          if (!wide) _groupList(),
          if (_groups != null && _groups!.isEmpty) ...[
            const SizedBox(height: 12),
            TRButton(
              label: 'Create your first Hive',
              icon: Icons.add_rounded,
              variant: TRButtonVariant.outline,
              onPressed: _newHive,
            ),
          ],
        ],
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Icon(Icons.hexagon_rounded, color: context.accent, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hives', style: TRText.display(24, c.text1)),
                      Text(
                        'Friends. Moments. Together.',
                        style: TRText.body(12, c.text3),
                      ),
                    ],
                  ),
                ),
                TRIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'New Hive',
                  onPressed: _newHive,
                ),
              ],
            ),
          ),
          if (!wide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Feed'),
                    selected: _view == 'feed',
                    onSelected: (_) => _showFeed(),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('My Hives'),
                    selected: _view == 'groups',
                    onSelected: (_) => setState(() => _view = 'groups'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                if (wide)
                  SizedBox(
                    width: 240,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        TRButton(
                          label: 'Community feed',
                          icon: Icons.forum_outlined,
                          variant: TRButtonVariant.ghost,
                          onPressed: _showFeed,
                        ),
                        const SizedBox(height: 20),
                        _groupList(),
                      ],
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _view == 'feed' ? 0 : 1,
                    children: [
                      TickerMode(
                        enabled: _view == 'feed',
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _Feed(repo: repo),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: main,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ Feed

class _Feed extends StatefulWidget {
  final HivesRepository repo;
  const _Feed({required this.repo});
  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  List<FeedPost> _posts = [];
  bool _loading = true, _more = false, _locked = true, _loadingMore = false;
  String _filter = 'all';
  String? _error;
  int _limit = 20;
  Map<String, Profile> _authors = {};
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    widget.repo.postingLocked().then((v) {
      if (mounted) setState(() => _locked = v);
    });
    _load();
    _ch = widget.repo.watchPosts(() => _load());
  }

  @override
  void dispose() {
    if (_ch != null) Supabase.instance.client.removeChannel(_ch!);
    super.dispose();
  }

  Future<void> _load({int? limit}) async {
    final l = limit ?? _limit;
    if (mounted) setState(() => _loadingMore = true);
    try {
      final p = await widget.repo.posts(limit: l, mine: _filter == 'mine');
      final authors = await widget.repo.profiles(p.map((x) => x.authorId));
      if (!mounted) return;
      setState(() {
        _limit = l;
        _posts = p;
        _authors = {..._authors, ...authors};
        _more = p.length == l;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _setFilter(String f) {
    setState(() {
      _filter = f;
      _loading = true;
    });
    _load(limit: 20);
  }

  Future<void> _compose([FeedPost? editing]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _Composer(repo: widget.repo, editing: editing),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final scope = AppScope.of(context);
    final canPost = scope.auth.isAdmin || !_locked;
    final me = scope.auth.user?.id;
    final visible = _posts
        .where((p) => !p.expired && (_filter != 'mine' || p.authorId == me))
        .toList();
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + mobileBarClearance(context),
        ),
        children: [
          Row(
            children: [
              TRAvatar(
                name: plainName(scope.auth.profile?.displayName ?? '?'),
                url: scope.auth.profile?.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Hoverable(
                  onTap: canPost ? () => _compose() : null,
                  builder: (_, h) => Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: h && canPost ? c.surface3 : c.surface2,
                      borderRadius: BorderRadius.circular(TRRadius.pill),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      canPost
                          ? 'Share something with your friends…'
                          : 'Posting is paused',
                      style: TRText.body(14, c.text3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              TRIconButton(
                icon: Icons.image_outlined,
                tooltip: 'Share photos or videos',
                onPressed: canPost ? () => _compose() : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Latest'),
                selected: _filter == 'all',
                onSelected: (_) => _setFilter('all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('My posts'),
                selected: _filter == 'mine',
                onSelected: (_) => _setFilter('mine'),
              ),
              const Spacer(),
              TRIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh feed',
                onPressed: () => _load(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              children: [
                Text('Could not load posts.', style: TRText.body(14, c.danger)),
                TextButton(
                  onPressed: () => _load(),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (visible.isEmpty)
            SizedBox(
              height: 260,
              child: EmptyState(
                icon: Icons.forum_outlined,
                title: _filter == 'mine'
                    ? 'Your moments belong here'
                    : 'A little quiet here',
                subtitle: canPost ? 'Share the first moment.' : null,
              ),
            )
          else
            for (final p in visible)
              _PostCard(
                key: ValueKey(p.id),
                repo: widget.repo,
                post: p,
                author: _authors[p.authorId],
                canManage: p.authorId == me || scope.auth.isAdmin,
                onEdit: () => _compose(p),
                onDeleted: () => _load(),
              ),
          if (_more && !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TRButton(
                label: _loadingMore ? 'Loading…' : 'Load more',
                variant: TRButtonVariant.outline,
                loading: _loadingMore,
                onPressed: () => _load(limit: _limit + 20),
              ),
            ),
        ],
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return DateFormat('MMM d').format(t);
}

class _PostCard extends StatefulWidget {
  final HivesRepository repo;
  final FeedPost post;
  final Profile? author;
  final bool canManage;
  final VoidCallback onEdit, onDeleted;
  const _PostCard({
    super.key,
    required this.repo,
    required this.post,
    this.author,
    required this.canManage,
    required this.onEdit,
    required this.onDeleted,
  });
  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  PostExtras? _x;
  bool _showComments = false, _sending = false;
  final _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final x = await widget.repo.extras(widget.post.id);
      if (mounted) setState(() => _x = x);
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    final mine = _x?.reactions[widget.repo.me];
    try {
      await widget.repo.react(widget.post.id, mine == emoji ? null : emoji);
      await _loadExtras();
    } catch (e) {
      if (mounted) showToast(context, _err(e), error: true);
    }
  }

  Future<void> _send() async {
    final t = _comment.text.trim();
    if (t.isEmpty || t.length > 2000) return;
    setState(() => _sending = true);
    try {
      await widget.repo.comment(widget.post.id, t);
      _comment.clear();
      await _loadExtras();
    } catch (e) {
      if (mounted) showToast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text(
          'This removes the post and its attachments for everyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.deletePost(widget.post);
      widget.onDeleted();
    } catch (e) {
      if (mounted) showToast(context, _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final p = widget.post;
    final a = widget.author;
    final me = widget.repo.me;
    final counts = <String, int>{};
    for (final e in _x?.reactions.values ?? const <String>[]) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final mine = _x?.reactions[me];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(TRRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TRAvatar(
                name: plainName(a?.displayName ?? '?'),
                url: a?.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FancyText(
                      a?.displayName ?? 'Member',
                      style: TRText.body(14, c.text1, w: FontWeight.w600),
                      maxLines: 1,
                    ),
                    Text(
                      [
                        _ago(p.createdAt),
                        p.visibility == 'everyone'
                            ? 'Everyone'
                            : (p.visibility == 'selected'
                                ? 'Selected friends'
                                : 'Friends'),
                        if (p.expiresAt != null)
                          'until ${DateFormat('MMM d').format(p.expiresAt!)}',
                      ].join(' · '),
                      style: TRText.body(12, c.text3),
                    ),
                  ],
                ),
              ),
              if (widget.canManage)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, color: c.text2),
                  onSelected: (v) => v == 'edit' ? widget.onEdit() : _delete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (p.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(p.body, style: TRText.body(15, c.text1)),
          ],
          if (p.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Attachments(repo: widget.repo, items: p.attachments),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final e in feedReactions)
                InkWell(
                  borderRadius: BorderRadius.circular(TRRadius.pill),
                  onTap: () => _react(e),
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: mine == e
                          ? context.accent.withValues(alpha: .18)
                          : c.surface2,
                      borderRadius: BorderRadius.circular(TRRadius.pill),
                      border: Border.all(
                        color: mine == e ? context.accent : c.border,
                      ),
                    ),
                    child: Text(
                      '$e${(counts[e] ?? 0) > 0 ? ' ${counts[e]}' : ''}',
                      style: TRText.body(13, c.text1),
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _showComments = !_showComments),
                icon: const Icon(Icons.mode_comment_outlined, size: 18),
                label: Text('${_x?.comments.length ?? 0}'),
              ),
            ],
          ),
          if (_showComments && _x != null) ...[
            const Divider(height: 24),
            for (final cm in _x!.comments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TRAvatar(
                      name: plainName(
                        _x!.people[cm.userId]?.displayName ?? '?',
                      ),
                      url: _x!.people[cm.userId]?.avatarUrl,
                      size: 30,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: FancyText(
                                  _x!.people[cm.userId]?.displayName ??
                                      'Member',
                                  style: TRText.body(
                                    13,
                                    c.text1,
                                    w: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _ago(cm.createdAt),
                                style: TRText.body(11, c.text3),
                              ),
                            ],
                          ),
                          Text(cm.body, style: TRText.body(14, c.text1)),
                        ],
                      ),
                    ),
                    if (cm.userId == me || widget.canManage)
                      TRIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Delete comment',
                        size: 30,
                        onPressed: () async {
                          try {
                            await widget.repo.deleteComment(cm.id);
                            _loadExtras();
                          } catch (e) {
                            if (context.mounted)
                              showToast(context, _err(e), error: true);
                          }
                        },
                      ),
                  ],
                ),
              ),
            if (_x!.commentsEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TRTextField(
                        controller: _comment,
                        hint: 'Write a comment…',
                        maxLength: 2000,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TRIconButton(
                      icon: Icons.send_rounded,
                      tooltip: 'Send',
                      onPressed: _sending ? null : _send,
                    ),
                  ],
                ),
              )
            else
              Text(
                'Comments are turned off for this post.',
                style: TRText.body(12, c.text3),
              ),
          ],
        ],
      ),
    );
  }
}

class _Attachments extends StatelessWidget {
  final HivesRepository repo;
  final List<FeedAttachment> items;
  const _Attachments({required this.repo, required this.items});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final images = items.where((a) => a.kind == 'image').toList();
    final others = items.where((a) => a.kind != 'image').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: images.length == 1 ? 1 : 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: images.length == 1 ? 4 / 3 : 1,
            children: [
              for (final a in images)
                FutureBuilder<String?>(
                  future: repo.mediaUrl(a.path),
                  builder: (_, s) => ClipRRect(
                    borderRadius: BorderRadius.circular(TRRadius.x2l),
                    child: s.data == null
                        ? Container(color: c.surface2)
                        : GestureDetector(
                            onTap: () =>
                                openImageViewer(context, s.data!, a.name),
                            child: Image.network(s.data!, fit: BoxFit.cover),
                          ),
                  ),
                ),
            ],
          ),
        for (final a in others)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: c.surface2,
              borderRadius: BorderRadius.circular(TRRadius.xl),
              child: ListTile(
                leading: Icon(
                  a.kind == 'video'
                      ? Icons.play_circle_outline_rounded
                      : Icons.insert_drive_file_outlined,
                  color: context.accent,
                ),
                title: Text(
                  a.name,
                  overflow: TextOverflow.ellipsis,
                  style: TRText.body(14, c.text1),
                ),
                subtitle: Text(
                  '${(a.size / 1048576).toStringAsFixed(1)} MB',
                  style: TRText.body(12, c.text3),
                ),
                onTap: () async {
                  final u = await repo.mediaUrl(a.path);
                  if (u != null)
                    launchUrl(
                      Uri.parse(u),
                      mode: LaunchMode.externalApplication,
                    );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Pending {
  final String name, type;
  final Uint8List bytes;
  _Pending(this.name, this.type, this.bytes);
}

class _Composer extends StatefulWidget {
  final HivesRepository repo;
  final FeedPost? editing;
  const _Composer({required this.repo, this.editing});
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  static const _durations = [
    ('1 hour', Duration(hours: 1)),
    ('1 day', Duration(days: 1)),
    ('3 days', Duration(days: 3)),
    ('1 week', Duration(days: 7)),
    ('1 month', Duration(days: 30)),
  ];
  late final _body = TextEditingController(text: widget.editing?.body ?? '');
  late final List<FeedAttachment> _existing = [...?widget.editing?.attachments];
  final List<_Pending> _pending = [];
  late String _visibility = widget.editing?.visibility ?? 'friends';
  late final Set<String> _selected = {...?widget.editing?.allowedUserIds};
  Duration? _duration = const Duration(days: 7);
  bool _comments = true, _commentsChanged = false, _busy = false;
  String _progress = '';
  List<Profile> _friends = [];

  @override
  void initState() {
    super.initState();
    widget.repo.friends().then((f) {
      if (mounted) setState(() => _friends = f);
    }).catchError((_) {});
    final ed = widget.editing;
    if (ed != null) {
      if (ed.expiresAt == null) _duration = null;
      widget.repo.extras(ed.id).then((x) {
        if (mounted && !_commentsChanged)
          setState(() => _comments = x.commentsEnabled);
      }).catchError((_) {});
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (r == null || !mounted) return;
    if (r.files.length + _pending.length + _existing.length > 10) {
      showToast(context, 'Up to 10 attachments per post.', error: true);
      return;
    }
    if (r.files.any((f) => f.size > 50 * 1024 * 1024)) {
      showToast(context, 'Each attachment must be under 50 MB.', error: true);
      return;
    }
    setState(() {
      for (final f in r.files) {
        if (f.bytes == null) continue;
        _pending.add(
          _Pending(
            f.name,
            lookupMimeType(f.name, headerBytes: f.bytes) ??
                'application/octet-stream',
            f.bytes!,
          ),
        );
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_body.text.trim().isEmpty && _pending.isEmpty && _existing.isEmpty)
      return;
    if (_visibility == 'selected' && _selected.isEmpty) {
      showToast(context, 'Choose at least one friend.', error: true);
      return;
    }
    setState(() => _busy = true);
    final uploaded = <FeedAttachment>[];
    var saved = false;
    try {
      for (final (i, f) in _pending.indexed) {
        setState(() => _progress = 'Uploading ${i + 1} of ${_pending.length}');
        uploaded.add(
          await widget.repo.uploadAttachment(f.name, f.bytes, f.type),
        );
      }
      setState(() => _progress = 'Publishing…');
      final id = await widget.repo.savePost(
        editing: widget.editing,
        body: _body.text,
        attachments: [..._existing, ...uploaded],
        visibility: _visibility,
        allowed: _selected.toList(),
        duration: _duration,
      );
      saved = true;
      if (widget.editing == null || _commentsChanged) {
        final ok = await widget.repo.setCommentsEnabled(id, _comments);
        if (!ok && mounted)
          showToast(
            context,
            'Post saved, but comment settings could not be saved.',
          );
      }
      if (widget.editing != null) {
        final removed = widget.editing!.attachments
            .where((a) => !_existing.any((x) => x.path == a.path))
            .map((a) => a.path)
            .toList();
        await widget.repo.removeFiles(removed);
      }
      if (mounted) {
        showToast(
          context,
          widget.editing != null ? 'Post updated' : 'Moment shared',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!saved)
        await widget.repo.removeFiles(uploaded.map((a) => a.path).toList());
      if (mounted) showToast(context, _err(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final isAdmin = AppScope.of(context).auth.isAdmin;
    return Dialog(
      backgroundColor: c.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TRRadius.x3l),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.editing != null ? 'Edit post' : 'Share a moment',
                    style: TRText.display(18, c.text1),
                  ),
                ),
                TRIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 4,
              maxLines: 10,
              maxLength: 10000,
              style: TRText.body(15, c.text1),
              decoration: InputDecoration(
                hintText: "What's happening?",
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TRRadius.xl),
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in _existing)
                  InputChip(
                    label: Text(a.name),
                    onDeleted: _busy
                        ? null
                        : () => setState(() => _existing.remove(a)),
                  ),
                for (final f in _pending)
                  InputChip(
                    label: Text(f.name),
                    onDeleted:
                        _busy ? null : () => setState(() => _pending.remove(f)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.attach_file_rounded, size: 16),
                  label: const Text('Add photos, videos or files'),
                  onPressed: _busy ? null : _pick,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Who can see this',
              style: TRText.body(13, c.text2, w: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'friends', label: Text('Friends')),
                ButtonSegment(value: 'everyone', label: Text('Everyone')),
                ButtonSegment(value: 'selected', label: Text('Choose')),
              ],
              selected: {_visibility},
              onSelectionChanged: (s) => setState(() => _visibility = s.first),
            ),
            if (_visibility == 'selected') ...[
              const SizedBox(height: 8),
              if (_friends.isEmpty)
                Text('No friends yet.', style: TRText.body(13, c.text3)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in _friends)
                    FilterChip(
                      label: Text(plainName(f.displayName)),
                      selected: _selected.contains(f.id),
                      onSelected: (v) => setState(
                        () => v ? _selected.add(f.id) : _selected.remove(f.id),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Keep it up for',
              style: TRText.body(13, c.text2, w: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in _durations)
                  ChoiceChip(
                    label: Text(d.$1),
                    selected: _duration == d.$2,
                    onSelected: (_) => setState(() => _duration = d.$2),
                  ),
                if (isAdmin)
                  ChoiceChip(
                    label: const Text('Forever'),
                    selected: _duration == null,
                    onSelected: (_) => setState(() => _duration = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Allow comments', style: TRText.body(14, c.text1)),
              value: _comments,
              onChanged: (v) => setState(() {
                _comments = v;
                _commentsChanged = true;
              }),
            ),
            const SizedBox(height: 8),
            TRButton(
              label: _busy
                  ? (_progress.isEmpty ? 'Saving…' : _progress)
                  : (widget.editing != null ? 'Save' : 'Share'),
              loading: _busy,
              large: true,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ Hive activities

const _modes = [
  ('capsule', 'Time capsules', Icons.inventory_2_outlined),
  ('decision', 'Decision trails', Icons.how_to_vote_outlined),
  ('mission', 'Shared missions', Icons.flag_outlined),
  ('catchup', 'Quiet catch-up', Icons.schedule_rounded),
];

class _Activities extends StatefulWidget {
  final HivesRepository repo;
  final HiveGroup hive;
  const _Activities({super.key, required this.repo, required this.hive});
  @override
  State<_Activities> createState() => _ActivitiesState();
}

class _ActivitiesState extends State<_Activities> {
  String _kind = 'capsule';
  HiveBoard? _board;
  Object? _error;
  Timer? _poll;
  Map<String, Profile> _people = {};

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await widget.repo.board(widget.hive.id);
      final ppl = await widget.repo.profiles(b.responses.map((r) => r.userId));
      if (mounted) {
        setState(() {
          _board = b;
          _error = null;
          _people = ppl;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _NewActivity(repo: widget.repo, chatId: widget.hive.id, kind: _kind),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final label = _modes.firstWhere((m) => m.$1 == _kind).$2;
    final list =
        _board?.activities.where((a) => a.kind == _kind).toList() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _modes)
              ChoiceChip(
                avatar: Icon(m.$3, size: 16),
                label: Text(m.$2),
                selected: _kind == m.$1,
                onSelected: (_) => setState(() => _kind = m.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TRText.body(15, c.text1, w: FontWeight.w600),
              ),
            ),
            TRIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onPressed: _load,
            ),
            TRButton(
              label: 'New',
              icon: Icons.add_rounded,
              onPressed: _board == null ? null : _create,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_board == null && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Text(
            'Hive activities are unavailable right now. Your Hives and feed still work.',
            style: TRText.body(13, c.text2),
          ),
        if (_board != null && list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Text('Nothing here yet', style: TRText.body(13, c.text3)),
            ),
          ),
        for (final a in list)
          _ActivityCard(
            key: ValueKey(a.id),
            repo: widget.repo,
            a: a,
            body: _board!.bodies[a.id],
            responses:
                _board!.responses.where((r) => r.activityId == a.id).toList(),
            admin: widget.hive.admin,
            people: _people,
            refresh: _load,
          ),
      ],
    );
  }
}

class _NewActivity extends StatefulWidget {
  final HivesRepository repo;
  final String chatId, kind;
  const _NewActivity({
    required this.repo,
    required this.chatId,
    required this.kind,
  });
  @override
  State<_NewActivity> createState() => _NewActivityState();
}

class _NewActivityState extends State<_NewActivity> {
  final _title = TextEditingController(),
      _body = TextEditingController(),
      _items = TextEditingController();
  DateTime? _unlock;
  bool _saving = false;

  Future<void> _pickUnlock() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (t == null) return;
    setState(
      () => _unlock = DateTime(d.year, d.month, d.day, t.hour, t.minute),
    );
  }

  Future<void> _save() async {
    final items = HivesRepository.parseItems(_items.text);
    final err = HivesRepository.validate(
      widget.kind,
      _title.text,
      _body.text,
      items,
      _unlock,
    );
    if (err != null) return showToast(context, err, error: true);
    setState(() => _saving = true);
    try {
      await widget.repo.createActivity(
        widget.chatId,
        widget.kind,
        _title.text,
        _body.text,
        items,
        _unlock,
      );
      if (mounted) {
        showToast(context, 'Published');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showToast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final k = widget.kind;
    final label = _modes.firstWhere((m) => m.$1 == k).$2.toLowerCase();
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: c.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TRRadius.xl),
          ),
        );
    return AlertDialog(
      backgroundColor: c.surface1,
      title: Text('New $label', style: TRText.display(18, c.text1)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Hive members only', style: TRText.body(12, c.text3)),
              const SizedBox(height: 12),
              TRTextField(controller: _title, hint: 'Title', maxLength: 140),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 8,
                maxLength: 10000,
                decoration: deco(k == 'catchup' ? 'Highlights' : 'Message'),
              ),
              if (k == 'decision' || k == 'mission')
                TextField(
                  controller: _items,
                  minLines: 3,
                  maxLines: 10,
                  decoration: deco(
                    k == 'decision'
                        ? 'One option per line'
                        : 'One task per line',
                  ),
                ),
              if (k == 'capsule')
                TRButton(
                  label: _unlock == null
                      ? 'Choose unlock time'
                      : 'Unlocks ${DateFormat('MMM d, yyyy HH:mm').format(_unlock!)}',
                  icon: Icons.lock_clock_outlined,
                  variant: TRButtonVariant.outline,
                  onPressed: _pickUnlock,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TRButton(
          label: _saving
              ? 'Publishing…'
              : (k == 'capsule' ? 'Seal capsule' : 'Publish'),
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

class _ActivityCard extends StatefulWidget {
  final HivesRepository repo;
  final HiveActivity a;
  final String? body;
  final List<HiveResponse> responses;
  final bool admin;
  final Map<String, Profile> people;
  final Future<void> Function() refresh;
  const _ActivityCard({
    super.key,
    required this.repo,
    required this.a,
    this.body,
    required this.responses,
    required this.admin,
    required this.people,
    required this.refresh,
  });
  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  bool _busy = false;
  final _reason = TextEditingController();

  Future<void> _respond(int slot, String action) async {
    setState(() => _busy = true);
    try {
      await widget.repo.respond(widget.a.id, slot, action, _reason.text);
      await widget.refresh();
    } catch (e) {
      if (mounted) showToast(context, _err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final ctl = TextEditingController();
    final outcome = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Record outcome'),
        content: TextField(
          controller: ctl,
          maxLength: 1000,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Final decision'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, ctl.text.trim()),
            child: const Text('Close decision'),
          ),
        ],
      ),
    );
    if (outcome == null || outcome.isEmpty) return;
    try {
      await widget.repo.closeDecision(widget.a.id, outcome);
      await widget.refresh();
    } catch (e) {
      if (mounted) showToast(context, _err(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final a = widget.a;
    final me = widget.repo.me;
    final rs = widget.responses;
    String who(String id) => id == me
        ? 'You'
        : plainName(widget.people[id]?.displayName ?? 'Member');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: BorderRadius.circular(TRRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  a.title,
                  style: TRText.body(15, c.text1, w: FontWeight.w600),
                ),
              ),
              Text(
                DateFormat('MMM d').format(a.createdAt),
                style: TRText.body(12, c.text3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (a.locked)
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: c.text3),
                const SizedBox(width: 6),
                Text(
                  'Unlocks ${a.unlockAt == null ? 'later' : DateFormat('MMM d, yyyy HH:mm').format(a.unlockAt!)}',
                  style: TRText.body(13, c.text2),
                ),
              ],
            )
          else if (widget.body?.isNotEmpty == true)
            SelectableText(widget.body!, style: TRText.body(14, c.text1))
          else if (a.kind == 'capsule')
            Text('Opening…', style: TRText.body(13, c.text3)),
          if (a.kind == 'decision') ...[
            const SizedBox(height: 10),
            for (final (i, item) in a.items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor:
                        rs.any((r) => r.userId == me && r.choice == i)
                            ? context.accent.withValues(alpha: .15)
                            : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TRRadius.xl),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onPressed: _busy || a.closedAt != null
                      ? null
                      : () => _respond(i, 'vote'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(item, style: TRText.body(14, c.text1)),
                      ),
                      Text(
                        '${rs.where((r) => r.choice == i).length}',
                        style: TRText.body(13, c.text2),
                      ),
                    ],
                  ),
                ),
              ),
            if (a.closedAt == null)
              TRTextField(
                controller: _reason,
                hint: 'Reason (optional)',
                maxLength: 1000,
              ),
            if (rs.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Vote trail · ${rs.length}',
                  style: TRText.body(13, c.text2),
                ),
                children: [
                  for (final r in rs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${who(r.userId)} · ${r.choice != null && r.choice! < a.items.length ? a.items[r.choice!] : ''}',
                        style: TRText.body(13, c.text1, w: FontWeight.w600),
                      ),
                      subtitle: r.reason.isEmpty
                          ? null
                          : Text(r.reason, style: TRText.body(12, c.text2)),
                    ),
                ],
              ),
            if (a.closedAt != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.accent, width: 2),
                  ),
                ),
                child: Text(
                  'Outcome\n${a.outcome ?? ''}',
                  style: TRText.body(13, c.text1),
                ),
              )
            else if (a.authorId == me || widget.admin)
              TextButton.icon(
                onPressed: _close,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Record outcome'),
              ),
          ],
          if (a.kind == 'mission') ...[
            const SizedBox(height: 6),
            for (final (i, item) in a.items.indexed)
              Builder(
                builder: (_) {
                  final r = rs.where((x) => x.slot == i).firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item,
                            style: TRText.body(
                              14,
                              r?.done == true ? c.text3 : c.text1,
                            ).copyWith(
                              decoration: r?.done == true
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (r == null)
                          OutlinedButton(
                            onPressed:
                                _busy ? null : () => _respond(i, 'claim'),
                            child: const Text('Claim'),
                          )
                        else if (r.userId == me) ...[
                          FilledButton.tonal(
                            onPressed: _busy
                                ? null
                                : () => _respond(
                                      i,
                                      r.done ? 'reopen' : 'complete',
                                    ),
                            child: Text(r.done ? 'Reopen' : 'Done'),
                          ),
                          TextButton(
                            onPressed:
                                _busy ? null : () => _respond(i, 'release'),
                            child: const Text('Release'),
                          ),
                        ] else
                          Text(
                            '${who(r.userId)} · ${r.done ? 'Complete' : 'Claimed'}',
                            style: TRText.body(12, c.text3),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}
