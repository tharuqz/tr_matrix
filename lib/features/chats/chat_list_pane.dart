import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';
import 'groups.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';

enum ChatFilter { all, unread, groups, archived }

/// Port of components/chat/chat-list.tsx (+ chat-filters).
class ChatListPane extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<ChatItem> onOpen;
  const ChatListPane({super.key, this.selectedId, required this.onOpen});
  @override
  State<ChatListPane> createState() => _ChatListPaneState();
}

class _ChatListPaneState extends State<ChatListPane> {
  List<ChatItem> _items = [];
  bool _loading = true;
  String _query = '';
  ChatFilter _filter = ChatFilter.all;
  RealtimeChannel? _channel;
  StreamSubscription<String>? _cacheSub;
  Timer? _debounce;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_channel == null) {
      final repo = AppScope.of(context).chats;
      _items = repo.cachedChats;
      _loading = _items.isEmpty && !repo.store.has(repo.ownerId, 'chats');
      _cacheSub = repo.changes.listen((_) {
        if (mounted)
          setState(() {
            _items = repo.cachedChats;
            _loading = false;
          });
      });
      _load();
      _channel = AppScope.of(context).chats.subscribeAll(() {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), () {
          repo.refreshChats();
          repo.retryPending();
        });
      });
    }
  }

  Future<void> _load() async {
    try {
      final items = await AppScope.of(context).chats.loadChats();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) showToast(context, 'Could not load chats', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _debounce?.cancel();
    _cacheSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<ChatItem> get _visible {
    final q = _query.toLowerCase();
    return _items.where((i) {
      if (q.isNotEmpty && !i.title.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        ChatFilter.all => !i.archived,
        ChatFilter.unread => i.unread > 0 && !i.archived,
        ChatFilter.groups => i.isGroup && !i.archived,
        ChatFilter.archived => i.archived,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final list = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TRMatrix', style: TRText.display(26, c.text1)),
                    Text('Messages', style: TRText.body(12, c.text3)),
                  ],
                ),
              ),
              TRIconButton(
                icon: Icons.group_add_outlined,
                tooltip: 'New group',
                onPressed: () => showNewGroupDialog(context),
              ),
              TRIconButton(
                icon: Icons.edit_square,
                tooltip: 'New chat',
                onPressed: () => context.go('/app/friends'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TRTextField(
            controller: _search,
            hint: 'Search chats',
            icon: Icons.search_rounded,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MatrixTabs(
            labels: const ['All', 'Unread', 'Groups', 'Archived'],
            selected: _filter.index,
            onChanged: (i) => setState(() => _filter = ChatFilter.values[i]),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              _loading
                  ? Center(
                    child: CircularProgressIndicator(
                      color: context.accent,
                      strokeWidth: 2,
                    ),
                  )
                  : list.isEmpty
                  ? const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No chats yet',
                    subtitle: 'Add friends in Contacts to start talking.',
                  )
                  : RefreshIndicator(
                    color: context.accent,
                    onRefresh: AppScope.of(context).chats.refreshChats,
                    child: Scrollbar(
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          8,
                          0,
                          8,
                          8 + mobileBarClearance(context),
                        ),
                        itemCount: list.length,
                        itemBuilder:
                            (_, i) => _ChatTile(
                              item: list[i],
                              selected: list[i].id == widget.selectedId,
                              onTap: () => widget.onOpen(list[i]),
                            ),
                      ),
                    ),
                  ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatItem item;
  final bool selected;
  final VoidCallback onTap;
  const _ChatTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  String _time(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    if (DateUtils.isSameDay(t, now)) return DateFormat.Hm().format(t);
    if (now.difference(t).inDays < 7) return DateFormat.E().format(t);
    return DateFormat('d MMM').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Hoverable(
      onTap: onTap,
      builder:
          (_, h) => AnimatedContainer(
            duration: matrixDuration(context, 180),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: AppScope.of(context).theme.compact ? 9 : 14,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TRRadius.xl),
              color:
                  selected
                      ? context.accent.withValues(alpha: .12)
                      : (h
                          ? c.text1.withValues(alpha: .04)
                          : Colors.transparent),
            ),
            child: Row(
              children: [
                TRAvatar(name: item.title, url: item.avatarUrl, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (item.isGroup)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.group_rounded,
                                size: 14,
                                color: c.text3,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TRText.body(
                                15,
                                c.text1,
                                w: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (item.muted)
                            Icon(
                              Icons.volume_off_rounded,
                              size: 14,
                              color: c.text3,
                            ),
                          const SizedBox(width: 6),
                          Text(
                            _time(item.lastMessageAt),
                            style: TRText.body(
                              12,
                              item.unread > 0 ? context.accent : c.text3,
                              w: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.preview.isEmpty ? 'Say hi 👋' : item.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TRText.body(13, c.text2),
                            ),
                          ),
                          if (item.unread > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              constraints: const BoxConstraints(minWidth: 20),
                              decoration: BoxDecoration(
                                color: context.accent,
                                borderRadius: BorderRadius.circular(
                                  TRRadius.pill,
                                ),
                              ),
                              child: Text(
                                item.unread > 99 ? '99+' : '${item.unread}',
                                textAlign: TextAlign.center,
                                style: TRText.body(
                                  11,
                                  TRAccent.on(context.accent),
                                  w: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
