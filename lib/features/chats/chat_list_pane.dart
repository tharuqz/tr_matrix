import '../../core/animated_emoji.dart';
import '../../core/desktop_menu.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_extras.dart';
import '../../data/models.dart';
import '../../data/pinned_chats_store.dart';
import '../../data/chat_folders_store.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';
import 'groups.dart';
import 'chat_manage.dart';
import 'package:go_router/go_router.dart';
import '../../core/motion.dart';
import '../../core/fancy.dart';
import '../../core/security/app_lock.dart';
import '../security/lock_screen.dart';

/// Built-in folders. Custom folders follow these in the tab row.
enum ChatFilter { all, hives, archived }

/// Port of components/chat/chat-list.tsx (+ chat-filters).
class ChatListPane extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<ChatItem> onOpen;
  const ChatListPane({super.key, this.selectedId, required this.onOpen});
  @override
  State<ChatListPane> createState() => _ChatListPaneState();
}

class _ChatListPaneState extends State<ChatListPane> {
  List<ChatItem> _raw = [];
  Set<String> _pinnedIds = {};
  StreamSubscription<Set<String>>? _pinnedSub;
  bool _loading = true;
  String _query = '';
  ChatFilter _filter = ChatFilter.all;

  /// Selected custom folder id (null = a built-in tab is selected).
  String? _folderId;
  List<ChatFolder> _folders = [];
  StreamSubscription<List<ChatFolder>>? _foldersSub;
  RealtimeChannel? _channel;
  StreamSubscription<String>? _cacheSub;
  Timer? _debounce;
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_channel == null) {
      final repo = AppScope.of(context).chats;
      _raw = repo.cachedChats;
      _loading = _raw.isEmpty && !repo.store.has(repo.ownerId, 'chats');
      // pinned chats: reactive overlay from SharedPreferences (trmatrix:pinned_chats:v1)
      AppLock.instance.addListener(_lockChanged);
      pinnedChatsStore.load();
      chatFoldersStore.load();
      _folders = chatFoldersStore.folders;
      _foldersSub = chatFoldersStore.stream.listen((f) {
        if (!mounted) return;
        setState(() {
          _folders = f;
          if (_folderId != null && !f.any((x) => x.id == _folderId))
            _folderId = null;
        });
      });
      _pinnedIds = pinnedChatsStore.pinned;
      _pinnedSub = pinnedChatsStore.stream.listen((ids) {
        if (mounted) setState(() => _pinnedIds = ids);
      });
      _cacheSub = repo.changes.listen((_) {
        if (mounted)
          setState(() {
            _raw = repo.cachedChats;
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

  void _lockChanged() {
    if (mounted) setState(() {});
  }

  List<ChatItem> get _itemsEff {
    final normalized = _raw
        .map((c) => c.copyWith(pinned: c.pinned || _pinnedIds.contains(c.id)))
        .toList();
    normalized.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return (b.lastMessageAt ?? DateTime(1970)).compareTo(
        a.lastMessageAt ?? DateTime(1970),
      );
    });
    return normalized;
  }

  Future<void> _load() async {
    try {
      final items = await AppScope.of(context).chats.loadChats();
      if (mounted) setState(() => _raw = items);
    } catch (e) {
      if (mounted) showToast(context, 'Could not load chats', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showChatMenu(ChatItem item) async {
    final c = context.tr;
    final repo = AppScope.of(context).chats;
    final pinned = _pinnedIds.contains(item.id) || item.pinned;
    await showAnchoredSheet(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) {
        Widget tile(
          IconData ic,
          String lab,
          VoidCallback tap, {
          bool danger = false,
        }) =>
            ListTile(
              leading: Icon(ic, color: danger ? c.danger : c.text1, size: 20),
              title: Text(lab,
                  style: TRText.body(14, danger ? c.danger : c.text1)),
              onTap: () {
                Navigator.pop(ctx);
                tap();
              },
            );
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: BorderRadius.circular(TRRadius.glass),
            border: Border.all(color: c.border),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                tile(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  pinned ? 'Unpin chat' : 'Pin chat',
                  () async {
                    await pinnedChatsStore.toggle(item.id);
                    if (ctx.mounted)
                      setState(() => _pinnedIds = pinnedChatsStore.pinned);
                    try {
                      await repo.togglePin(item.id);
                    } catch (_) {}
                    if (mounted) setState(() => _raw = repo.cachedChats);
                  },
                ),
                tile(
                  item.muted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  item.muted ? 'Unmute' : 'Mute',
                  () async {
                    await repo.toggleMute(item.id);
                    if (mounted) setState(() => _raw = repo.cachedChats);
                  },
                ),
                tile(
                  item.archived
                      ? Icons.unarchive_rounded
                      : Icons.archive_outlined,
                  item.archived ? 'Unarchive' : 'Archive',
                  () async {
                    await repo.toggleArchive(item.id);
                    if (mounted) setState(() => _raw = repo.cachedChats);
                  },
                ),
                tile(
                  Icons.create_new_folder_outlined,
                  'Add to folder',
                  () => _pickFolderFor(item),
                ),
                tile(
                  Icons.lock_outline_rounded,
                  'Lock & hide chat',
                  () => lockChat(context, item.id),
                ),
                tile(Icons.clear_all_rounded, 'Clear history',
                    () => confirmClearHistory(context, item.id)),
                if (!item.isGroup && item.otherUserId != null)
                  tile(Icons.block_rounded, 'Block / unblock user',
                      () => toggleBlock(context, item),
                      danger: true),
                tile(Icons.delete_outline_rounded, 'Delete chat', () async {
                  if (await confirmDeleteChat(context, item)) {
                    if (mounted) setState(() => _raw = repo.cachedChats);
                    if (mounted && widget.selectedId == item.id)
                      GoRouter.of(context).go('/app');
                  }
                }, danger: true),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    AppLock.instance.removeListener(_lockChanged);
    _channel?.unsubscribe();
    _debounce?.cancel();
    _pinnedSub?.cancel();
    _foldersSub?.cancel();
    _cacheSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  int get _lockedCount =>
      _filter == ChatFilter.all && _folderId == null && _query.isEmpty
          ? _itemsEff.where((i) => AppLock.instance.isChatLocked(i.id)).length
          : 0;

  Future<void> _openLocked() async {
    if (!await confirmUnlock(context)) return;
    if (!mounted) return;
    final locked =
        _itemsEff.where((i) => AppLock.instance.isChatLocked(i.id)).toList();
    final c = context.tr;
    final picked = await showAnchoredSheet<ChatItem>(
      large: true,
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(TRRadius.glass),
          border: Border.all(color: c.border),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 18, color: context.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Locked chats',
                      style: TRText.body(15, c.text1, w: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              for (final it in locked)
                ListTile(
                  leading: TRAvatar(
                    name: it.title,
                    url: it.avatarUrl,
                    size: 40,
                  ),
                  title: Text(
                    plainName(it.title),
                    style: TRText.body(14, c.text1, w: FontWeight.w600),
                  ),
                  trailing: IconButton(
                    tooltip: 'Unlock & show in list',
                    icon: Icon(
                      Icons.lock_open_rounded,
                      color: c.text2,
                      size: 20,
                    ),
                    onPressed: () async {
                      await AppLock.instance.setChatLocked(it.id, false);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  onTap: () => Navigator.pop(ctx, it),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) widget.onOpen(picked);
  }

  /// Create (folder == null) or edit a folder: name + chat checklist.
  Future<void> _editFolder({ChatFolder? folder, String? preselect}) async {
    final c = context.tr;
    final name = TextEditingController(text: folder?.name ?? '');
    final picked = <String>{
      ...?folder?.chatIds,
      if (preselect != null) preselect,
    };
    final chats =
        _itemsEff.where((i) => !AppLock.instance.isChatLocked(i.id)).toList();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          backgroundColor: c.surface1,
          title: Text(folder == null ? 'New folder' : 'Edit folder'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: ChatFoldersStore.maxNameLength,
                  decoration: InputDecoration(
                    hintText: 'Folder name',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chats',
                  style: TRText.body(12, c.text3, w: FontWeight.w600),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final it in chats)
                          CheckboxListTile(
                            dense: true,
                            value: picked.contains(it.id),
                            onChanged: (v) => setD(
                              () => v == true
                                  ? picked.add(it.id)
                                  : picked.remove(it.id),
                            ),
                            secondary: TRAvatar(
                              name: it.title,
                              url: it.avatarUrl,
                              size: 32,
                            ),
                            title: Text(
                              plainName(it.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final done = folder == null
                    ? (await chatFoldersStore.create(
                          name.text,
                          picked.toList(),
                        )) !=
                        null
                    : await chatFoldersStore.rename(folder.id, name.text);
                if (done && folder != null)
                  await chatFoldersStore.setChats(folder.id, picked.toList());
                if (done) {
                  if (d.mounted) Navigator.pop(d, true);
                } else {
                  setD(
                    () => error = name.text.trim().isEmpty
                        ? 'Enter a name'
                        : 'That name is already used',
                  );
                }
              },
              child: Text(folder == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (ok == true && folder == null && mounted) {
      final created = chatFoldersStore.folders.lastOrNull;
      if (created != null) setState(() => _folderId = created.id);
    }
  }

  Future<void> _folderMenu(ChatFolder folder) async {
    final c = context.tr;
    final action = await showAnchoredSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.surface1,
          borderRadius: BorderRadius.circular(TRRadius.glass),
          border: Border.all(color: c.border),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: c.text1),
                  title: const Text('Edit folder'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: c.danger),
                  title: Text(
                    'Delete folder',
                    style: TextStyle(color: c.danger),
                  ),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _editFolder(folder: folder);
    if (action == 'delete') {
      await chatFoldersStore.delete(folder.id);
      if (mounted)
        showToast(context, 'Folder deleted. Chats were not removed.');
    }
  }

  Future<void> _pickFolderFor(ChatItem item) async {
    final c = context.tr;
    if (_folders.isEmpty) {
      await _editFolder(preselect: item.id);
      return;
    }
    await showAnchoredSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => StreamBuilder<List<ChatFolder>>(
        stream: chatFoldersStore.stream,
        initialData: chatFoldersStore.folders,
        builder: (ctx, snap) => Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: c.surface1,
            borderRadius: BorderRadius.circular(TRRadius.glass),
            border: Border.all(color: c.border),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in snap.data ?? const <ChatFolder>[])
                    CheckboxListTile(
                      value: f.chatIds.contains(item.id),
                      onChanged: (_) =>
                          chatFoldersStore.toggleChat(f.id, item.id),
                      title: Text(f.name),
                      secondary: Icon(Icons.folder_outlined, color: c.text2),
                    ),
                  ListTile(
                    leading: Icon(Icons.add_rounded, color: context.accent),
                    title: const Text('New folder'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _editFolder();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<ChatItem> get _visible {
    final q = _query.toLowerCase();
    return _itemsEff.where((i) {
      if (AppLock.instance.isChatLocked(i.id)) return false;
      if (q.isNotEmpty && !i.title.toLowerCase().contains(q)) return false;
      final folder = _folders.where((f) => f.id == _folderId).firstOrNull;
      if (folder != null) return folder.chatIds.contains(i.id);
      return switch (_filter) {
        ChatFilter.all => !i.archived,
        ChatFilter.hives => i.isGroup && !i.archived,
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
              // Web header has a single Hexagon (New Hive) icon — no extra compose icons.
              TRIconButton(
                icon: Icons.hexagon_outlined,
                tooltip: 'New Hive',
                onPressed: () => showNewGroupDialog(context),
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
          child: Row(
            children: [
              Expanded(
                child: MatrixTabs(
                  labels: [
                    'All',
                    'Hives',
                    'Archived',
                    for (final f in _folders) f.name,
                  ],
                  selected: _folderId == null
                      ? _filter.index
                      : ChatFilter.values.length +
                          _folders.indexWhere((f) => f.id == _folderId),
                  onChanged: (i) => setState(() {
                    if (i < ChatFilter.values.length) {
                      _filter = ChatFilter.values[i];
                      _folderId = null;
                    } else {
                      _folderId = _folders[i - ChatFilter.values.length].id;
                    }
                  }),
                  onLongPress: (i) {
                    if (i >= ChatFilter.values.length)
                      _folderMenu(_folders[i - ChatFilter.values.length]);
                  },
                ),
              ),
              TRIconButton(
                icon: Icons.add_rounded,
                tooltip: 'New folder',
                onPressed: () => _editFolder(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.accent,
                    strokeWidth: 2,
                  ),
                )
              : list.isEmpty
                  ? (_folderId != null
                      ? EmptyState(
                          icon: Icons.folder_open_rounded,
                          title: 'This folder is empty',
                          subtitle:
                              'Long-press a chat and choose Add to folder.',
                        )
                      : const EmptyState(
                          icon: Icons.forum_outlined,
                          title: 'No chats yet',
                          subtitle: 'Add friends in Contacts to start talking.',
                        ))
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
                          itemCount: list.length + (_lockedCount > 0 ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (_lockedCount > 0) {
                              if (i == 0)
                                return _LockedFolder(
                                  count: _lockedCount,
                                  onTap: _openLocked,
                                );
                              i -= 1;
                            }
                            final item = list[i];
                            return _ChatTile(
                              item: item,
                              selected: item.id == widget.selectedId,
                              onTap: () => widget.onOpen(item),
                              onLongPress: () => _showChatMenu(item),
                            );
                          },
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

// legacy _showSheet preserved for backward-compat if referenced elsewhere
Future<void> _showSheet(BuildContext context, ChatItem item) async {
  final repo = AppScope.of(context).chats;
  final navigator = Navigator.of(context);
  await showAnchoredSheet<void>(
    context: context,
    backgroundColor: context.tr.surface1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(TRRadius.xl)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(item.pinned ? 'Unpin' : 'Pin'),
            onTap: () async {
              navigator.pop();
              await repo.togglePin(item.id);
            },
          ),
          ListTile(
            leading: Icon(
              item.muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            ),
            title: Text(item.muted ? 'Unmute' : 'Mute'),
            onTap: () async {
              navigator.pop();
              await repo.toggleMute(item.id);
            },
          ),
          ListTile(
            leading: Icon(
              item.archived ? Icons.unarchive_rounded : Icons.archive_rounded,
            ),
            title: Text(item.archived ? 'Unarchive' : 'Archive'),
            onTap: () async {
              navigator.pop();
              await repo.toggleArchive(item.id);
            },
          ),
          if (item.unread > 0)
            ListTile(
              leading: const Icon(Icons.done_all_rounded),
              title: const Text('Mark as read'),
              onTap: () async {
                navigator.pop();
                await repo.markChatRead(item.id);
              },
            ),
        ],
      ),
    ),
  );
}

class _ChatTile extends StatelessWidget {
  final ChatItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _ChatTile({
    required this.item,
    required this.selected,
    required this.onTap,
    this.onLongPress,
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
    return GestureDetector(
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Hoverable(
        onTap: onTap,
        builder: (_, h) => AnimatedContainer(
          duration: matrixDuration(context, 180),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: AppScope.of(context).theme.compact ? 9 : 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TRRadius.xl),
            color: selected
                ? context.accent.withValues(alpha: .12)
                : (h ? c.text1.withValues(alpha: .04) : Colors.transparent),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  TRAvatar(name: item.title, url: item.avatarUrl, size: 48),
                  if (item.pinned)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: context.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.push_pin,
                          size: 10,
                          color: TRAccent.on(context.accent),
                        ),
                      ),
                    ),
                ],
              ),
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
                            style: TRText.body(15, c.text1, w: FontWeight.w600),
                          ),
                        ),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.pinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.push_pin_rounded,
                                    size: 12,
                                    color: context.accent,
                                  ),
                                ),
                              if (item.muted)
                                Icon(
                                  Icons.volume_off_rounded,
                                  size: 14,
                                  color: c.text3,
                                ),
                            ],
                          ),
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
                          child: AnimatedEmojiText(
                            item.preview.isEmpty ? 'Say hi 👋' : item.preview,
                            maxLines: 1,
                            jumbo: false,
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
      ),
    );
  }
}

/// Lock a chat: it disappears from the list and opens only with your PIN / fingerprint.
Future<void> lockChat(BuildContext context, String chatId) async {
  final l = AppLock.instance;
  if (!l.enabled && !await showSetPinDialog(context)) return;
  await l.setChatLocked(chatId, true);
  if (context.mounted)
    showToast(context, 'Chat locked. Find it under "Locked chats".');
}

class _LockedFolder extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _LockedFolder({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.tr, a = context.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TRRadius.xl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.withValues(alpha: .14),
                  border: Border.all(color: a.withValues(alpha: .35)),
                ),
                child: Icon(Icons.lock_rounded, color: a, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Locked chats',
                  style: TRText.body(15, c.text1, w: FontWeight.w600),
                ),
              ),
              Text('$count', style: TRText.body(13, c.text3)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: c.text3),
            ],
          ),
        ),
      ),
    );
  }
}
