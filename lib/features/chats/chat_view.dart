import '../../core/desktop_menu.dart';
import 'dart:async';

import '../../core/motion.dart';
import '../../data/chat_repository.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../zones/zone_page.dart';
import '../../core/notifications.dart';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:ui' as ui;
import '../../core/theme/chat_appearance.dart';
import '../../core/theme/chat_pattern.dart';
import '../../core/app_scope.dart';
import '../../core/animated_emoji.dart';
import '../../core/fancy.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_actions.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/text_style_picker.dart';
import '../../widgets/zone_button.dart';
import '../../widgets/last_seen_text.dart';
import '../../widgets/live_status_icon.dart';
import 'groups.dart';
import 'media/attachment.dart';
import 'media/stickers.dart';
import 'media/emoji_panel.dart';
import 'media/voice.dart';
import 'message_actions.dart';
import 'wallpaper.dart';
import '../../data/pinned_repository.dart';
import '../../data/chat_extras.dart';

const _maxUpload = 50 * 1024 * 1024;

/// Port of routes/app.chat.$chatId.tsx — text, replies, files, photos, voice notes,
/// stickers, reactions, edit, delete for everyone, groups and wallpaper.
class ChatView extends StatefulWidget {
  final String chatId;
  final String title;
  final String? avatarUrl;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;
  final void Function(String kind)? onCall;
  const ChatView({
    super.key,
    required this.chatId,
    required this.title,
    this.avatarUrl,
    this.subtitle,
    this.onBack,
    this.onToggleInfo,
    this.onCall,
  });
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<Message> _messages = [];
  bool _loading = true;
  Message? _replyTo;
  Message? _editing;
  RealtimeChannel? _channel;
  String? _boundChat;
  ChatRepository? _repo;
  StreamSubscription<String>? _cacheSub;
  bool _sending = false;
  Map<String, List<String>> _reactions = {};
  Map<String, String> _myReactions = {};
  bool _isGroup = false;
  String? _peerId;
  Map<String, ({bool delivered, bool seen})> _receipts = {};
  RealtimeChannel? _receiptCh;
  String? _wallpaper;
  Map<String, Profile> _senders = {};
  bool _recording = false, _stickers = false, _dragging = false;
  int _uploading = 0;
  TextStyleSpec _pendingStyle = plainStyle;
  ChatAppearanceStore? _appearanceStore;
  ChatAppearance get _appearance =>
      _appearanceStore?.value ?? defaultAppearance;

  @override
  void initState() {
    super.initState();
    wallpaperChanges.addListener(_onWallpaperChange);
  }

  void _onWallpaperChange() {
    final v = wallpaperChanges.value;
    if (v != null && v.$1 == widget.chatId && mounted)
      setState(() => _wallpaper = v.$2);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ChatView old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId) _bind();
  }

  void _bind() {
    NotificationService.instance?.activeChatId = widget.chatId;
    final uid = AppScope.of(context).auth.user?.id ?? 'signed-out';
    _appearanceStore?.dispose();
    _appearanceStore = ChatAppearanceStore(uid, widget.chatId)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    if (_boundChat == widget.chatId) return;
    final oldId = _boundChat;
    if (oldId != null) _repo?.drafts[oldId] = _input.text;
    _boundChat = widget.chatId;
    _channel?.unsubscribe();
    _cacheSub?.cancel();
    _replyTo = _editing = null;
    final repo = AppScope.of(context).chats;
    _repo = repo;
    final id = widget.chatId;
    _input.text = repo.drafts[id] ?? '';
    _messages = repo.cachedMessages(id);
    _loading =
        _messages.isEmpty && !repo.store.has(repo.ownerId, 'messages:$id');
    _cacheSub = repo.changes.listen((key) {
      if (!mounted || _boundChat != id) return;
      if (key == id || key == '*')
        setState(() {
          _messages = repo.cachedMessages(id);
          _loading = false;
        });
    });
    repo.loadMessages(id).then((m) {
      if (!mounted || _boundChat != id) return;
      setState(() {
        _messages = m;
        _loading = false;
      });
      repo.markRead(m);
      _loadReceipts();
    }).catchError((_) {
      if (mounted && _boundChat == id) setState(() => _loading = false);
    });
    _loadReactions();
    repo.chatRow(id).then((row) async {
      if (!mounted || _boundChat != id || row == null) return;
      setState(() {
        _isGroup = row['is_group'] == true;
        final ua = row['user_a'] as String?, ub = row['user_b'] as String?;
        _peerId = _isGroup ? null : (ua == repo.ownerId ? ub : ua);
        _wallpaper = row['wallpaper_url'] as String?;
      });
      if (_isGroup) {
        final ms = await repo.groupMembers(id);
        if (mounted && _boundChat == id)
          setState(
            () => _senders = {for (final m in ms) m.profile.id: m.profile},
          );
      }
    }).catchError((_) {});
    _channel = repo.subscribeChat(
      id,
      onUpsert: (msg) {
        if (!mounted || _boundChat != id) return;
        setState(() {
          final i = _messages.indexWhere((x) => x.id == msg.id);
          if (i >= 0) {
            _messages = [..._messages]..[i] = msg;
          } else {
            _messages = [..._messages, msg];
          }
        });
        repo.markRead([msg]);
        if (msg.senderId == repo.ownerId) _loadReceipts();
      },
      onReactions: _loadReactions,
    );
    if (_receiptCh != null) Supabase.instance.client.removeChannel(_receiptCh!);
    // Live sent → delivered → seen updates (same filter as the website).
    _receiptCh = Supabase.instance.client
        .channel('receipts-chat:$id:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: id,
          ),
          callback: (p) {
            final r = p.newRecord;
            final mid = r['message_id']?.toString();
            if (!mounted ||
                _boundChat != id ||
                mid == null ||
                r['user_id'] == repo.ownerId) return;
            final prev = _receipts[mid];
            final seen = (prev?.seen ?? false) || r['read_at'] != null;
            final del =
                (prev?.delivered ?? false) || seen || r['delivered_at'] != null;
            setState(
              () =>
                  _receipts = {..._receipts, mid: (delivered: del, seen: seen)},
            );
          },
        )
        .subscribe();
  }

  Future<void> _loadReceipts() async {
    final repo = _repo;
    final id = _boundChat;
    if (repo == null || id == null) return;
    final mine = _messages
        .where((m) => m.senderId == repo.ownerId && !m.pending)
        .map((m) => m.id)
        .toList();
    final ids = mine.length > 150 ? mine.sublist(mine.length - 150) : mine;
    final r = await repo.fetchReceipts(ids);
    if (mounted && _boundChat == id)
      setState(() => _receipts = {..._receipts, ...r});
  }

  MsgStatus _statusOf(Message m) {
    if (m.pending) return MsgStatus.sending;
    final r = _receipts[m.id];
    if (r?.seen == true) return MsgStatus.seen;
    if (r?.delivered == true) return MsgStatus.delivered;
    return MsgStatus.sent;
  }

  Future<void> _loadReactions() async {
    final id = widget.chatId;
    final (all, mine) = await AppScope.of(context).chats.loadReactions(id);
    if (mounted && _boundChat == id)
      setState(() {
        _reactions = all;
        _myReactions = mine;
      });
  }

  @override
  void dispose() {
    wallpaperChanges.removeListener(_onWallpaperChange);
    if (NotificationService.instance?.activeChatId == widget.chatId)
      NotificationService.instance?.activeChatId = null;
    _channel?.unsubscribe();
    if (_receiptCh != null) Supabase.instance.client.removeChannel(_receiptCh!);
    _cacheSub?.cancel();
    _appearanceStore?.dispose();
    final id = _boundChat;
    if (id != null) _repo?.drafts[id] = _input.text;
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _me => AppScope.of(context).auth.user!.id;

  Future<void> _send() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;
    final encoded = encodeStyled(raw, _pendingStyle);
    final repo = AppScope.of(context).chats;
    if (_editing != null) {
      final target = _editing!;
      setState(() {
        _messages = _messages
            .map(
              (m) => m.id == target.id
                  ? _copy(m, content: encoded, edited: true)
                  : m,
            )
            .toList();
        _editing = null;
      });
      _input.clear();
      try {
        await repo.editMessage(target.id, encoded);
      } catch (_) {
        if (mounted) showToast(context, 'Could not edit message', error: true);
      }
      return;
    }
    if (_sending) return;
    _sending = true;
    final reply = _replyTo;
    final id = widget.chatId;
    try {
      await repo.sendText(id, encoded, replyToId: reply?.id);
      if (!mounted || _boundChat != id) return;
      setState(() {
        _messages = repo.cachedMessages(id);
        _replyTo = null;
      });
      if (_input.text.trim() == raw) _input.clear();
      repo.drafts[id] = _input.text;
      _focus.requestFocus();
    } catch (_) {
      if (mounted)
        showToast(
          context,
          'Could not save message on this device. Your text is still here.',
          error: true,
        );
    } finally {
      _sending = false;
    }
  }

  Message _copy(Message m, {String? content, bool? edited, bool? deleted}) =>
      Message(
        id: m.id,
        chatId: m.chatId,
        senderId: m.senderId,
        content: deleted == true ? null : (content ?? m.content),
        mediaUrl: deleted == true ? null : m.mediaUrl,
        mediaType: deleted == true ? null : m.mediaType,
        mediaName: deleted == true ? null : m.mediaName,
        mediaSize: deleted == true ? null : m.mediaSize,
        createdAt: m.createdAt,
        deleted: deleted ?? m.deleted,
        edited: edited ?? m.edited,
        replyToId: m.replyToId,
      );

  /// Upload and send one file (photo, document, voice note or sticker).
  Future<void> _sendFile(
    String name,
    Uint8List bytes, {
    String? mime,
    String? caption,
  }) async {
    if (bytes.length > _maxUpload) {
      showToast(context, '$name is bigger than 50 MB', error: true);
      return;
    }
    final type = mime ??
        lookupMimeType(name, headerBytes: bytes) ??
        'application/octet-stream';
    final reply = _replyTo;
    setState(() {
      _uploading++;
      _replyTo = null;
    });
    try {
      final real = await AppScope.of(context).chats.sendMedia(
            widget.chatId,
            name: name,
            bytes: bytes,
            mime: type,
            caption: caption,
            replyToId: reply?.id,
          );
      if (mounted)
        setState(
          () => _messages = [..._messages.where((m) => m.id != real.id), real],
        );
    } catch (_) {
      if (mounted) showToast(context, 'Could not send $name', error: true);
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  Future<void> _pickFiles({bool images = false}) async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: images ? FileType.media : FileType.any,
    );
    if (r == null) return;
    for (final f in r.files) {
      if (f.bytes != null) await _sendFile(f.name, f.bytes!);
    }
  }

  void _attachMenu() {
    final c = context.tr;
    showAnchoredSheet(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 420),
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
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photos & videos'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles(images: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('File'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles();
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Sticker'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _stickers = true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper_rounded),
                title: const Text('Chat wallpaper'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openWallpaper();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openWallpaper() => showWallpaperPicker(
        context,
        widget.chatId,
        (p) => setState(() => _wallpaper = p),
      );

  Future<void> _react(Message m, String? emoji) async {
    final old = _myReactions[m.id];
    setState(() {
      final list = [...(_reactions[m.id] ?? <String>[])];
      if (old != null) list.remove(old);
      if (emoji != null) list.add(emoji);
      _reactions = {..._reactions, m.id: list};
      _myReactions = {..._myReactions}..remove(m.id);
      if (emoji != null) _myReactions[m.id] = emoji;
    });
    try {
      await AppScope.of(context).chats.setReaction(widget.chatId, m.id, emoji);
    } catch (_) {
      if (mounted) showToast(context, "Couldn't save reaction", error: true);
    }
  }

  Future<void> _forward(Message m) async {
    final repo = AppScope.of(context).chats;
    final c = context.tr;
    final chats = repo.cachedChats.where((x) => x.id != widget.chatId).toList();
    final target = await showAnchoredSheet<ChatItem>(
      large: true,
      context: context,
      backgroundColor: c.surface1,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
              title: Text('Forward to…',
                  style: TRText.body(15, c.text1, w: FontWeight.w700))),
          for (final it in chats)
            ListTile(
              leading: TRAvatar(name: it.title, url: it.avatarUrl, size: 36),
              title: Text(plainName(it.title),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, it),
            ),
        ]),
      ),
    );
    if (target == null || !mounted) return;
    try {
      await repo.forwardMessage(m, target.id);
      if (mounted)
        showToast(context, 'Forwarded to ${plainName(target.title)}');
    } catch (_) {
      if (mounted) showToast(context, 'Could not forward', error: true);
    }
  }

  void _actions(Message m) {
    if (m.pending) return;
    showMessageActions(
      context,
      msg: m,
      mine: m.senderId == _me,
      myReaction: _myReactions[m.id],
      onReact: (e) => _react(m, e),
      onAction: (a) async {
        switch (a) {
          case MsgAction.reply:
            setState(() => _replyTo = m);
            _focus.requestFocus();
          case MsgAction.forward:
            await _forward(m);
          case MsgAction.pin:
            try {
              await PinnedRepository(Supabase.instance.client, _me ?? '')
                  .pin(widget.chatId, m.id);
              if (mounted) showToast(context, 'Message pinned');
            } catch (_) {
              if (mounted)
                showToast(
                    context, 'Could not pin (max ${PinnedRepository.maxPins})',
                    error: true);
            }
          case MsgAction.copy:
            await Clipboard.setData(ClipboardData(text: m.content ?? ''));
            if (mounted) showToast(context, 'Copied');
          case MsgAction.edit:
            setState(() {
              _editing = m;
              _replyTo = null;
              _input.text = m.content ?? '';
            });
            _focus.requestFocus();
          case MsgAction.delete:
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Delete for everyone?'),
                content: const Text(
                  'This message will be removed for everyone in the chat.',
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
            if (ok != true || !mounted) return;
            setState(
              () => _messages = _messages
                  .map((x) => x.id == m.id ? _copy(x, deleted: true) : x)
                  .toList(),
            );
            try {
              await AppScope.of(context).chats.deleteForEveryone(m.id);
            } catch (_) {
              if (mounted) showToast(context, 'Could not delete', error: true);
            }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);
    final me = AppScope.of(context).auth.user?.id;
    final reversed = _messages.reversed.toList();

    Widget body = Column(
      children: [
        _Header(
          chatId: widget.chatId,
          title: widget.title,
          avatarUrl: widget.avatarUrl,
          subtitle: _isGroup ? '${_senders.length} members' : '',
          peerId: _peerId,
          onBack: widget.onBack,
          onTitle: _isGroup
              ? () => showGroupInfo(context, widget.chatId)
              : widget.onToggleInfo,
          onInfo: widget.onToggleInfo,
          onCall: widget.onCall,
          onWallpaper: _openWallpaper,
          onZone: () => openZone(context, widget.chatId, widget.title),
        ),
        if (AppScope.of(context).chats.offline ||
            _messages.any((m) => m.pending))
          Material(
            color: context.tr.surface2,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(
                _messages.any((m) => m.pending)
                    ? 'Messages waiting to send'
                    : 'Offline · saved messages',
              ),
              trailing: IconButton(
                tooltip: 'Retry connection',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  final repo = AppScope.of(context).chats;
                  repo.retryPending();
                  repo.refreshMessages(widget.chatId);
                },
              ),
            ),
          ),
        if (_uploading > 0)
          LinearProgressIndicator(
            minHeight: 2,
            color: context.accent,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.accent,
                    strokeWidth: 2,
                  ),
                )
              : _messages.isEmpty
                  ? const EmptyState(
                      icon: Icons.waving_hand_outlined,
                      title: 'No messages yet',
                      subtitle: 'Say hello!',
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: EdgeInsets.symmetric(
                          horizontal: mobile ? 10 : 24,
                          vertical: 16,
                        ),
                        itemCount: reversed.length,
                        itemBuilder: (_, i) {
                          final m = reversed[i];
                          final older =
                              i + 1 < reversed.length ? reversed[i + 1] : null;
                          final showDay = older == null ||
                              !DateUtils.isSameDay(
                                  older.createdAt, m.createdAt);
                          final replied = m.replyToId == null
                              ? null
                              : _messages
                                  .where((x) => x.id == m.replyToId)
                                  .firstOrNull;
                          final showName = _isGroup &&
                              m.senderId != me &&
                              (older == null ||
                                  older.senderId != m.senderId ||
                                  showDay);
                          return MatrixReveal(
                            key: ValueKey(m.id),
                            child: Column(
                              children: [
                                if (showDay) _DayDivider(m.createdAt),
                                _Bubble(
                                  appearance:
                                      (_appearanceStore?.customized ?? false)
                                          ? _appearance
                                          : null,
                                  msg: m,
                                  mine: m.senderId == me,
                                  status: _statusOf(m),
                                  replied: replied,
                                  senderName: showName
                                      ? (_senders[m.senderId]?.displayName ??
                                          'Member')
                                      : null,
                                  reactions: _reactions[m.id] ?? const [],
                                  myReaction: _myReactions[m.id],
                                  onReply: () {
                                    setState(() => _replyTo = m);
                                    _focus.requestFocus();
                                  },
                                  onActions: () => _actions(m),
                                  onToggleReaction: (e) => _react(
                                      m, _myReactions[m.id] == e ? null : e),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
        _Composer(
          controller: _input,
          focus: _focus,
          replyTo: _replyTo,
          editing: _editing,
          recording: _recording,
          showStickers: _stickers,
          uid: me ?? '',
          pendingStyle: _pendingStyle,
          onStyleChanged: (s) => setState(() => _pendingStyle = s),
          appearance: _appearance,
          onCancelReply: () => setState(() {
            _replyTo = null;
            if (_editing != null) _input.clear();
            _editing = null;
          }),
          onSend: _send,
          onAttach: _attachMenu,
          onMic: () => setState(() {
            _recording = true;
            _stickers = false;
          }),
          onToggleStickers: () => setState(() => _stickers = !_stickers),
          onVoiceCancel: () => setState(() => _recording = false),
          onVoiceSend: (n, b, t) {
            setState(() => _recording = false);
            _sendFile(n, b, mime: t);
          },
          onSticker: (s) {
            setState(() => _stickers = false);
            _sendFile(s.name, s.bytes, mime: s.mime);
          },
        ),
      ],
    );

    // Drag files from the computer onto the chat to send them.
    body = DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) async {
        setState(() => _dragging = false);
        for (final f in d.files) {
          await _sendFile(f.name, await f.readAsBytes());
        }
      },
      child: Stack(
        children: [
          body,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(TRRadius.glass),
                    border: Border.all(color: context.accent, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      'Drop files to send',
                      style: TRText.display(22, context.tr.text1),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_replyTo != null || _editing != null || _stickers) {
            setState(() {
              _replyTo = null;
              if (_editing != null) _input.clear();
              _editing = null;
              _stickers = false;
            });
          } else {
            widget.onBack?.call();
          }
        },
      },
      child: body,
    );
    if (mobile && widget.onBack != null) {
      body = GestureDetector(
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 600) widget.onBack!();
        },
        child: body,
      );
    }
    final ap = _appearance;
    final themed = (_appearanceStore?.customized ?? false) &&
        (_wallpaper == null || _wallpaper!.isEmpty) &&
        (ap.background == 'preset' || ap.background == 'solid');
    if (themed) {
      final c = context.tr;
      return Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: ap.background == 'preset'
                ? BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: chatPresetGradient(ap.preset),
                    ),
                  )
                : BoxDecoration(color: c.surface2),
          ),
          if (ap.dim > 0)
            Container(color: c.bg.withValues(alpha: ap.dim / 100)),
          ChatPatternLayer(ap: ap, accent: context.accent),
          body,
        ],
      );
    }
    if ((_appearanceStore?.customized ?? false) && ap.effect != 'none') {
      body = Stack(fit: StackFit.expand, children: [
        ChatPatternLayer(ap: ap, accent: context.accent),
        body,
      ]);
    }
    return ChatWallpaper(path: _wallpaper, child: body);
  }
}

class _Header extends StatelessWidget {
  final String title, subtitle, chatId;
  final String? avatarUrl, peerId;
  final VoidCallback? onBack, onInfo, onTitle, onWallpaper, onZone;
  final void Function(String kind)? onCall;
  const _Header({
    required this.title,
    required this.subtitle,
    required this.chatId,
    this.peerId,
    this.avatarUrl,
    this.onBack,
    this.onInfo,
    this.onCall,
    this.onTitle,
    this.onWallpaper,
    this.onZone,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      padding: EdgeInsets.fromLTRB(
        onBack != null ? 4 : 20,
        MediaQuery.paddingOf(context).top + 10,
        12,
        10,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: c.text2, size: 20),
                tooltip: 'Back (Esc)',
                onPressed: onBack,
              ),
            ),
          if (onBack != null) const SizedBox(width: 8),
          Expanded(
            child: Hoverable(
              onTap: onTitle ?? onInfo,
              builder: (_, __) => Row(
                children: [
                  TRAvatar(name: title, url: avatarUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FancyText(
                          title,
                          style: TRText.body(16, c.text1, w: FontWeight.w700),
                          maxLines: 1,
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TRText.body(12, c.text3),
                          )
                        else
                          LastSeenText(userId: peerId),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: c.surface2.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(TRRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TRIconButton(
                  icon: Icons.phone_outlined,
                  tooltip: 'Voice call',
                  onPressed: onCall == null ? null : () => onCall!('voice'),
                ),
                TRIconButton(
                  icon: Icons.videocam_outlined,
                  tooltip: 'Video call',
                  onPressed: onCall == null ? null : () => onCall!('video'),
                ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: c.border.withValues(alpha: .5),
                ),
                LiveZoneButton(chatId: chatId, onPressed: () => onZone?.call()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  final DateTime d;
  const _DayDivider(this.d);
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final now = DateTime.now();
    final label = DateUtils.isSameDay(d, now)
        ? 'Today'
        : DateUtils.isSameDay(d, now.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : DateFormat('EEEE, d MMM y').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(TRRadius.pill),
          border: Border.all(color: c.border),
        ),
        child: Text(label, style: TRText.body(12, c.text2, w: FontWeight.w600)),
      ),
    );
  }
}

String _replyLabel(Message m) {
  if (m.deleted) return 'Message deleted';
  if (m.content?.isNotEmpty ?? false) return m.content!;
  if (isStickerName(m.mediaName)) return 'Sticker';
  final t = m.mediaType ?? '';
  if (t.startsWith('image/')) return '📷 Photo';
  if (t.startsWith('audio/')) return '🎤 Voice note';
  return '📎 ${m.mediaName ?? 'File'}';
}

class _Bubble extends StatelessWidget {
  final Message msg;
  final bool mine;
  final MsgStatus status;
  final Message? replied;
  final String? senderName;
  final List<String> reactions;
  final String? myReaction;
  final VoidCallback onReply, onActions;
  final void Function(String) onToggleReaction;

  /// The chat's saved theme; null keeps the original bubble look.
  final ChatAppearance? appearance;
  const _Bubble({
    this.appearance,
    required this.msg,
    required this.mine,
    this.status = MsgStatus.sent,
    this.replied,
    this.senderName,
    required this.reactions,
    this.myReaction,
    required this.onReply,
    required this.onActions,
    required this.onToggleReaction,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final c = context.tr, a = context.accent;
          final sticker = !msg.deleted && isStickerName(msg.mediaName);
          final fg = c.text1;
          final maxW =
              (constraints.maxWidth - (Responsive.isMobile(context) ? 32 : 72))
                  .clamp(0.0, 520.0);
          final hasMedia = !msg.deleted && msg.mediaUrl != null;
          final text = msg.deleted ? 'This message was deleted' : msg.content;

          final counts = <String, int>{};
          for (final e in reactions) {
            counts[e] = (counts[e] ?? 0) + 1;
          }

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (senderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    senderName!,
                    style: TRText.body(12, a, w: FontWeight.w700),
                  ),
                ),
              if (replied != null && !msg.deleted)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(TRRadius.sm),
                    border: Border(
                      left:
                          BorderSide(color: fg.withValues(alpha: .6), width: 3),
                    ),
                  ),
                  child: Text(
                    _replyLabel(replied!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TRText.body(12, fg.withValues(alpha: .8)),
                  ),
                ),
              if (hasMedia)
                Padding(
                  padding: EdgeInsets.only(bottom: text == null ? 0 : 6),
                  child: Attachment(msg: msg, fg: fg),
                ),
              if (text != null)
                Builder(
                  builder: (_) {
                    final s = decodeStyled(text);
                    final bubbleStyle = TRText.body(
                      15,
                      s.color ?? (msg.deleted ? fg.withValues(alpha: .6) : fg),
                    ).copyWith(
                        fontStyle: msg.deleted ? FontStyle.italic : null);
                    // Plain text stays selectable; styled text needs gradient ShaderMask.
                    if (s.font == 'normal' && s.fx == null && s.color == null) {
                      // Emoji play as live motion inline, not only when alone.
                      if (!msg.deleted && AnimatedEmojiText.hasAnimated(text)) {
                        return AnimatedEmojiText(text, style: bubbleStyle);
                      }
                      return SelectableText(text, style: bubbleStyle);
                    }
                    final plain = s.text.isEmpty ? text : s.text;
                    // Motion fx use FancyText's animated gradient; custom color uses solid.
                    return FancyText(
                      encodeFancy(plain, s.fx, s.color),
                      style: bubbleStyle,
                    );
                  },
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg.edited && !msg.deleted)
                    Text(
                      'edited · ',
                      style: TRText.body(10, fg.withValues(alpha: .6)),
                    ),
                  Text(
                    DateFormat('HH:mm').format(msg.createdAt),
                    style: TRText.body(10, fg.withValues(alpha: .7)),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    LiveStatusIcon(
                      status: status,
                      muted: fg.withValues(alpha: .7),
                      size: 12,
                    ),
                  ],
                ],
              ),
            ],
          );

          final box = Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: sticker
                ? const EdgeInsets.all(2)
                : const EdgeInsets.fromLTRB(12, 9, 12, 7),
            decoration: sticker
                ? null
                : BoxDecoration(
                    color: mine
                        ? ((appearance == null
                                ? null
                                : chatMineColor(appearance!, c.surface1)) ??
                            Color.alphaBlend(
                                a.withValues(alpha: .20), c.surface1))
                        : ((appearance == null
                                ? null
                                : chatReceivedColor(appearance!, c.surface1)) ??
                            c.bubbleIn),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(appearance == null
                          ? TRRadius.x2l
                          : chatBubbleRadius(appearance!)),
                      topRight: Radius.circular(appearance == null
                          ? TRRadius.x2l
                          : chatBubbleRadius(appearance!)),
                      bottomLeft: Radius.circular(mine
                          ? (appearance == null
                              ? TRRadius.x2l
                              : chatBubbleRadius(appearance!))
                          : 6),
                      bottomRight: Radius.circular(mine
                          ? 6
                          : (appearance == null
                              ? TRRadius.x2l
                              : chatBubbleRadius(appearance!))),
                    ),
                  ),
            child: content,
          );

          final bubble = Hoverable(
            builder: (_, h) => Row(
              mainAxisAlignment:
                  mine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (mine && !Responsive.isMobile(context))
                  SizedBox(
                    width: 64,
                    child: Visibility(
                      visible: h && !msg.deleted,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Row(
                        children: [
                          TRIconButton(
                            icon: Icons.more_horiz_rounded,
                            tooltip: 'More',
                            size: 30,
                            onPressed: onActions,
                          ),
                          TRIconButton(
                            icon: Icons.reply_rounded,
                            tooltip: 'Reply',
                            size: 30,
                            onPressed: onReply,
                          ),
                        ],
                      ),
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Column(
                    crossAxisAlignment: mine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onLongPress: onActions,
                        onSecondaryTap: onActions,
                        child: box,
                      ),
                      if (counts.isNotEmpty && !msg.deleted)
                        Wrap(
                          spacing: 4,
                          children: [
                            for (final e in counts.entries)
                              InkWell(
                                borderRadius:
                                    BorderRadius.circular(TRRadius.pill),
                                onTap: () => onToggleReaction(e.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: myReaction == e.key
                                        ? a.withValues(alpha: .25)
                                        : c.surface2,
                                    borderRadius: BorderRadius.circular(
                                      TRRadius.pill,
                                    ),
                                    border: Border.all(
                                      color: myReaction == e.key ? a : c.border,
                                    ),
                                  ),
                                  child: Text(
                                    e.value > 1 ? '${e.key} ${e.value}' : e.key,
                                    style: TRText.body(13, c.text1),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (!mine && !Responsive.isMobile(context))
                  SizedBox(
                    width: 64,
                    child: Visibility(
                      visible: h && !msg.deleted,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Row(
                        children: [
                          TRIconButton(
                            icon: Icons.reply_rounded,
                            tooltip: 'Reply',
                            size: 30,
                            onPressed: onReply,
                          ),
                          TRIconButton(
                            icon: Icons.more_horiz_rounded,
                            tooltip: 'More',
                            size: 30,
                            onPressed: onActions,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );

          return Dismissible(
            key: ValueKey('swipe-${msg.id}'),
            direction: DismissDirection.startToEnd,
            confirmDismiss: (_) async {
              HapticFeedback.lightImpact();
              onReply();
              return false;
            },
            background: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(Icons.reply_rounded, color: c.text2),
              ),
            ),
            child: bubble,
          );
        },
      );
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final Message? replyTo, editing;
  final bool recording, showStickers;
  final String uid;
  final VoidCallback onCancelReply,
      onSend,
      onAttach,
      onMic,
      onToggleStickers,
      onVoiceCancel;
  final void Function(String, Uint8List, String) onVoiceSend;
  final void Function(LocalSticker) onSticker;
  final TextStyleSpec? pendingStyle;
  final ValueChanged<TextStyleSpec>? onStyleChanged;
  final ChatAppearance? appearance;
  const _Composer({
    required this.controller,
    required this.focus,
    this.replyTo,
    this.editing,
    required this.recording,
    required this.showStickers,
    required this.uid,
    required this.onCancelReply,
    required this.onSend,
    required this.onAttach,
    required this.onMic,
    required this.onToggleStickers,
    required this.onVoiceCancel,
    required this.onVoiceSend,
    required this.onSticker,
    this.pendingStyle,
    this.onStyleChanged,
    this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final mobile = Responsive.isMobile(context);
    final banner = editing != null
        ? 'Editing message'
        : (replyTo != null ? 'Replying: ${_replyLabel(replyTo!)}' : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showStickers && !recording)
          EmojiStickerPanel(
              uid: uid, controller: controller, onSticker: onSticker),
        if (banner != null && !recording)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(TRRadius.lg),
                border: Border(
                  left: BorderSide(color: context.accent, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    editing != null ? Icons.edit_outlined : Icons.reply_rounded,
                    size: 16,
                    color: c.text2,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      banner,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TRText.body(13, c.text2),
                    ),
                  ),
                  TRIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Cancel (Esc)',
                    size: 30,
                    onPressed: onCancelReply,
                  ),
                ],
              ),
            ),
          ),
        if (recording)
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              8 + MediaQuery.paddingOf(context).bottom,
            ),
            child: VoiceRecorderBar(
              onCancel: onVoiceCancel,
              onSend: onVoiceSend,
            ),
          )
        else
          Builder(
            builder: (context) {
              final ap = appearance ?? defaultAppearance;
              final bg = composerEffectiveColor(
                ap,
                context.tr,
              ).withValues(alpha: composerStrength(ap));
              final rad = composerRadius(ap);
              final border = composerBorder(ap, context.tr);
              final onCol = composerOnColor(ap, context.tr);
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  4,
                  12,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(rad),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(rad),
                        border:
                            border != null ? Border.all(color: border) : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TRIconButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Attach',
                            onPressed: onAttach,
                          ),
                          TRIconButton(
                            icon: Icons.emoji_emotions_outlined,
                            tooltip: 'Emoji & stickers',
                            active: showStickers,
                            onPressed: onToggleStickers,
                          ),
                          if (pendingStyle != null && onStyleChanged != null)
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: pendingStyle!.isStyled
                                    ? context.accent.withValues(alpha: .14)
                                    : Colors.transparent,
                              ),
                              child: IconButton(
                                tooltip: 'Text style',
                                icon: Icon(
                                  Icons.text_fields_rounded,
                                  size: 20,
                                  color: pendingStyle!.isStyled
                                      ? context.accent
                                      : Colors.white70,
                                ),
                                onPressed: () {
                                  var local = pendingStyle!;
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) => Dialog(
                                      backgroundColor: c.surface1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 360,
                                          maxHeight: 620,
                                        ),
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(14),
                                          // StatefulBuilder so taps update the picker right away.
                                          child: StatefulBuilder(
                                            builder: (ctx, setLocal) =>
                                                _InlineStyleSheet(
                                              value: local,
                                              sample: controller.text,
                                              onChanged: (v) {
                                                setLocal(() => local = v);
                                                onStyleChanged!(v);
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CallbackShortcuts(
                              bindings: {
                                const SingleActivator(LogicalKeyboardKey.enter):
                                    onSend,
                              },
                              child: TextField(
                                controller: controller,
                                focusNode: focus,
                                minLines: 1,
                                maxLines: 5,
                                textInputAction: mobile
                                    ? TextInputAction.newline
                                    : TextInputAction.none,
                                style: TRText.body(15, onCol),
                                cursorColor: context.accent,
                                decoration: InputDecoration(
                                  hintText: 'Write a message...',
                                  hintStyle: TRText.body(
                                    15,
                                    onCol.withValues(alpha: .45),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller,
                            builder: (_, v, __) {
                              final empty =
                                  v.text.trim().isEmpty && editing == null;
                              return Hoverable(
                                tooltip: empty
                                    ? 'Record voice note'
                                    : 'Send (Enter)',
                                onTap: empty ? onMic : onSend,
                                builder: (_, h) => AnimatedContainer(
                                  duration: matrixDuration(context, 150),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: empty
                                        ? Colors.white.withValues(alpha: .12)
                                        : context.accent,
                                    shape: BoxShape.circle,
                                    boxShadow: !empty && h
                                        ? TRShadow.glow(context.accent)
                                        : null,
                                  ),
                                  child: Icon(
                                    empty
                                        ? Icons.mic_rounded
                                        : (editing != null
                                            ? Icons.check_rounded
                                            : Icons.send_rounded),
                                    size: 20,
                                    color: empty
                                        ? Colors.white70
                                        : TRAccent.on(context.accent),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _InlineStyleSheet extends StatelessWidget {
  final TextStyleSpec value;
  final ValueChanged<TextStyleSpec> onChanged;
  final String sample;
  const _InlineStyleSheet({
    required this.value,
    required this.onChanged,
    required this.sample,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final colors = [...TRAccent.swatches, c.text1];
    final preview = applyFont(
      sample.trim().isEmpty ? 'TR MATRIX' : sample.trim(),
      value.font,
    );
    final encoded = encodeFancy(preview, value.fx, value.color);
    Widget chip(String label, bool on, VoidCallback tap) => ActionChip(
          label: Text(
            label,
            style: TRText.body(13, on ? TRAccent.on(context.accent) : c.text1),
          ),
          backgroundColor: on ? context.accent : c.surface2,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          onPressed: tap,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: FancyText(
            encoded,
            style: TRText.body(16, c.text1, w: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Text('Effect', style: TRText.body(11, c.text3, w: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(
              'None',
              value.fx == null,
              () => onChanged(value.copyWith(clearFx: true)),
            ),
            for (final fx in motionFx)
              chip(
                motionLabels[fx]!,
                value.fx == fx,
                () => onChanged(value.copyWith(fx: fx)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Color', style: TRText.body(11, c.text3, w: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ActionChip(
              label: Text(
                'Auto',
                style: TRText.body(
                  12,
                  value.color == null ? TRAccent.on(context.accent) : c.text1,
                ),
              ),
              backgroundColor:
                  value.color == null ? context.accent : c.surface2,
              side: BorderSide(color: c.border),
              shape: const StadiumBorder(),
              onPressed: () => onChanged(value.copyWith(clearColor: true)),
            ),
            for (final col in colors)
              GestureDetector(
                onTap: () => onChanged(value.copyWith(color: col)),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.border),
                    boxShadow: value.color == col
                        ? [
                            BoxShadow(
                              color: context.accent,
                              blurRadius: 0,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Font', style: TRText.body(11, c.text3, w: FontWeight.w600)),
        const SizedBox(height: 6),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.8,
          children: [
            for (final f in fancyFonts)
              ActionChip(
                label: Text(
                  applyFont(fontLabels[f]!, f),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TRText.body(
                    12,
                    value.font == f ? TRAccent.on(context.accent) : c.text1,
                  ),
                ),
                backgroundColor: value.font == f ? context.accent : c.surface2,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () => onChanged(value.copyWith(font: f)),
              ),
          ],
        ),
        if (value.isStyled) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onChanged(plainStyle),
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: BorderSide(color: c.border),
              ),
              child: Text('Reset style', style: TRText.body(13, c.text1)),
            ),
          ),
        ],
      ],
    );
  }
}
