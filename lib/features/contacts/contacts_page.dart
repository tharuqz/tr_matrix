import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_scope.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';

/// Port of routes/app.friends.tsx — friends, requests, search & add.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  int _tab = 0; // 0 friends, 1 requests, 2 add
  List<ContactRow> _friends = [], _incoming = [], _outgoing = [];
  List<Profile> _results = [];
  bool _loading = true;
  Timer? _debounce;
  final _q = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    try {
      final r = await AppScope.of(context).contacts.load();
      if (!mounted) return;
      setState(() {
        _friends = r.friends;
        _incoming = r.incoming;
        _outgoing = r.outgoing;
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await AppScope.of(context).contacts.search(v);
      if (mounted) setState(() => _results = r);
    });
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) showToast(context, ok);
      await _load();
    } catch (e) {
      if (mounted) showToast(context, 'Something went wrong', error: true);
    }
  }

  Future<void> _message(Profile p) async {
    final id = await AppScope.of(context).chats.getOrCreateDirect(p.id);
    if (!mounted) return;
    context.go(
      '/app/chat/$id',
      extra: ChatItem(
        id: id,
        isGroup: false,
        title: p.displayName,
        avatarUrl: p.avatarUrl,
        otherUserId: p.id,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final repo = AppScope.of(context).contacts;
    final friendIds = {
      ..._friends,
      ..._incoming,
      ..._outgoing,
    }.map((r) => r.profile.id).toSet();

    List<Widget> rows;
    if (_tab == 0) {
      rows = _friends.isEmpty
          ? [
              const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No friends yet',
                subtitle: 'Find people in the Add tab.',
              ),
            ]
          : _friends
              .map(
                (f) => _PersonTile(
                  profile: f.profile,
                  actions: [
                    TRIconButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      tooltip: 'Message',
                      onPressed: () => _message(f.profile),
                    ),
                    TRIconButton(
                      icon: Icons.person_remove_outlined,
                      tooltip: 'Remove',
                      onPressed: () =>
                          _run(() => repo.remove(f.rel.id), 'Removed'),
                    ),
                  ],
                ),
              )
              .toList();
    } else if (_tab == 1) {
      rows = [
        if (_incoming.isEmpty && _outgoing.isEmpty)
          const EmptyState(
            icon: Icons.mark_email_unread_outlined,
            title: 'No requests',
          ),
        for (final r in _incoming)
          _PersonTile(
            profile: r.profile,
            subtitle: 'Wants to be friends',
            actions: [
              TRButton(
                label: 'Accept',
                onPressed: () => _run(
                  () => repo.setStatus(r.rel.id, 'accepted'),
                  'Friend added',
                ),
              ),
              const SizedBox(width: 6),
              TRButton(
                label: 'Decline',
                variant: TRButtonVariant.outline,
                onPressed: () => _run(() => repo.remove(r.rel.id), 'Declined'),
              ),
            ],
          ),
        for (final r in _outgoing)
          _PersonTile(
            profile: r.profile,
            subtitle: 'Request sent',
            actions: [
              TRButton(
                label: 'Cancel',
                variant: TRButtonVariant.ghost,
                onPressed: () => _run(() => repo.remove(r.rel.id), 'Cancelled'),
              ),
            ],
          ),
      ];
    } else {
      rows = [
        TRTextField(
          controller: _q,
          hint: 'Search by username or name',
          icon: Icons.search_rounded,
          onChanged: _search,
        ),
        const SizedBox(height: 12),
        for (final p in _results)
          _PersonTile(
            profile: p,
            actions: [
              if (friendIds.contains(p.id))
                Text('Connected', style: TRText.body(13, c.text3))
              else
                TRButton(
                  label: 'Add',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: () =>
                      _run(() => repo.sendRequest(p.id), 'Request sent'),
                ),
            ],
          ),
      ];
    }

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  Responsive.isMobile(context) ? 16 : 28,
                  20,
                  16,
                ),
                child: Text('Contacts', style: TRText.display(24, c.text1)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: MatrixTabs(
                  labels: [
                    'Friends (${_friends.length})',
                    'Requests${_incoming.isEmpty ? '' : ' (${_incoming.length})'}',
                    'Add',
                  ],
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: context.accent,
                          strokeWidth: 2,
                        ),
                      )
                    : Scrollbar(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            4,
                            16,
                            16 + mobileBarClearance(context),
                          ),
                          children: rows,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  final Profile profile;
  final String? subtitle;
  final List<Widget> actions;
  const _PersonTile({
    required this.profile,
    this.subtitle,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Hoverable(
      builder: (_, h) => Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: h ? c.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(TRRadius.x2l),
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TRAvatar(
                  name: profile.displayName,
                  url: profile.avatarUrl,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TRText.body(15, c.text1, w: FontWeight.w600),
                      ),
                      Text(
                        subtitle ?? '@${profile.username}',
                        style: TRText.body(13, c.text2),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 480) ...actions,
              ],
            ),
            if (MediaQuery.sizeOf(context).width < 480)
              Padding(
                padding: const EdgeInsets.only(left: 56, top: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: actions),
              ),
          ],
        ),
      ),
    );
  }
}
