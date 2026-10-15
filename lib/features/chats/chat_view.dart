import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../zones/zone_page.dart';
import '../../core/notifications.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_scope.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_actions.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'groups.dart';
import 'media/attachment.dart';
import 'media/stickers.dart';
import 'media/voice.dart';
import 'message_actions.dart';
import 'wallpaper.dart';

const _maxUpload = 50 * 1024 * 1024;

/// Port of routes/app.chat.$chatId.tsx — text, replies, files, photos, voice notes,
/// stickers, reactions, edit, delete for everyone, groups and wallpaper.
class ChatView extends StatefulWidget {
  final String chatId;
  final String title;
  final String? avatarUrl;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;
  final void Function(String kind)? onCall;
  const ChatView({super.key, required this.chatId, required this.title, this.avatarUrl, this.onBack, this.onToggleInfo, this.onCall});
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
  Map<String, List<String>> _reactions = {};
  Map<String, String> _myReactions = {};
  bool _isGroup = false;
  String? _wallpaper;
  Map<String, Profile> _senders = {};
  bool _recording = false, _stickers = false, _dragging = false;
  int _uploading = 0;

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
    if (_boundChat == widget.chatId) return;
    _boundChat = widget.chatId;
    _channel?.unsubscribe();
    _loading = true;
    _messages = [];
    _replyTo = _editing = null;
    final repo = AppScope.of(context).chats;
    final id = widget.chatId;
    repo.loadMessages(id).then((m) {
      if (!mounted || _boundChat != id) return;
      setState(() {
        _messages = m;
        _loading = false;
      });
      repo.markRead(m);
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
    _loadReactions();
    repo.chatRow(id).then((row) async {
      if (!mounted || row == null) return;
      setState(() {
        _isGroup = row['is_group'] == true;
        _wallpaper = row['wallpaper_url'] as String?;
      });
      if (_isGroup) {
        final ms = await repo.groupMembers(id);
        if (mounted) setState(() => _senders = {for (final m in ms) m.profile.id: m.profile});
      }
    }).catchError((_) {});
    _channel = repo.subscribeChat(id, onUpsert: (msg) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((x) => x.id == msg.id);
        if (i >= 0) {
          _messages = [..._messages]..[i] = msg;
        } else {
          _messages = [..._messages, msg];
        }
      });
      repo.markRead([msg]);
    }, onReactions: _loadReactions);
  }

  Future<void> _loadReactions() async {
    final (all, mine) = await AppScope.of(context).chats.loadReactions(widget.chatId);
    if (mounted) setState(() { _reactions = all; _myReactions = mine; });
  }

  @override
  void dispose() {
    if (NotificationService.instance?.activeChatId == widget.chatId) NotificationService.instance?.activeChatId = null;
    _channel?.unsubscribe();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _me => AppScope.of(context).auth.user!.id;

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final repo = AppScope.of(context).chats;
    if (_editing != null) {
      final target = _editing!;
      setState(() {
        _messages = _messages
            .map((m) => m.id == target.id ? _copy(m, content: text, edited: true) : m)
            .toList();
        _editing = null;
      });
      _input.clear();
      try {
        await repo.editMessage(target.id, text);
      } catch (_) {
        if (mounted) showToast(context, 'Could not edit message', error: true);
      }
      return;
    }
    final reply = _replyTo;
    final tmp = Message(
      id: 'tmp-${DateTime.now().microsecondsSinceEpoch}',
      chatId: widget.chatId,
      senderId: _me,
      content: text,
      createdAt: DateTime.now(),
      replyToId: reply?.id,
      pending: true,
    );
    setState(() {
      _messages = [..._messages, tmp];
      _replyTo = null;
    });
    _input.clear();
    _focus.requestFocus();
    try {
      final real = await repo.sendText(widget.chatId, text, replyToId: reply?.id);
      if (!mounted) return;
      setState(() => _messages = [..._messages.where((m) => m.id != tmp.id && m.id != real.id), real]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages = _messages.where((m) => m.id != tmp.id).toList());
      showToast(context, 'Failed to send', error: true);
    }
  }

  Message _copy(Message m, {String? content, bool? edited, bool? deleted}) => Message(
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
  Future<void> _sendFile(String name, Uint8List bytes, {String? mime, String? caption}) async {
    if (bytes.length > _maxUpload) {
      showToast(context, '$name is bigger than 50 MB', error: true);
      return;
    }
    final type = mime ?? lookupMimeType(name, headerBytes: bytes) ?? 'application/octet-stream';
    final reply = _replyTo;
    setState(() {
      _uploading++;
      _replyTo = null;
    });
    try {
      final real = await AppScope.of(context)
          .chats
          .sendMedia(widget.chatId, name: name, bytes: bytes, mime: type, caption: caption, replyToId: reply?.id);
      if (mounted) setState(() => _messages = [..._messages.where((m) => m.id != real.id), real]);
    } catch (_) {
      if (mounted) showToast(context, 'Could not send $name', error: true);
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  Future<void> _pickFiles({bool images = false}) async {
    final r = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true, type: images ? FileType.media : FileType.any);
    if (r == null) return;
    for (final f in r.files) {
      if (f.bytes != null) await _sendFile(f.name, f.bytes!);
    }
  }

  void _attachMenu() {
    final c = context.tr;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 420),
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: c.surface1, borderRadius: BorderRadius.circular(TRRadius.glass), border: Border.all(color: c.border)),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photos & videos'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles(images: true);
                }),
            ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('File'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles();
                }),
            ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Sticker'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _stickers = true);
                }),
            ListTile(
                leading: const Icon(Icons.wallpaper_rounded),
                title: const Text('Chat wallpaper'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openWallpaper();
                }),
          ]),
        ),
      ),
    );
  }

  void _openWallpaper() => showWallpaperPicker(context, widget.chatId, (p) => setState(() => _wallpaper = p));

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
                content: const Text('This message will be removed for everyone in the chat.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok != true || !mounted) return;
            setState(() => _messages = _messages.map((x) => x.id == m.id ? _copy(x, deleted: true) : x).toList());
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

    Widget body = Column(children: [
      _Header(
        title: widget.title,
        avatarUrl: widget.avatarUrl,
        subtitle: _isGroup ? '${_senders.length} members · tap for info' : 'tap for info',
        onBack: widget.onBack,
        onTitle: _isGroup ? () => showGroupInfo(context, widget.chatId) : widget.onToggleInfo,
        onInfo: widget.onToggleInfo,
        onCall: widget.onCall,
        onWallpaper: _openWallpaper,
        onZone: () => openZone(context, widget.chatId, widget.title),
      ),
      if (_uploading > 0) LinearProgressIndicator(minHeight: 2, color: context.accent, backgroundColor: Colors.transparent),
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: context.accent, strokeWidth: 2))
            : _messages.isEmpty
                ? const EmptyState(icon: Icons.waving_hand_outlined, title: 'No messages yet', subtitle: 'Say hello!')
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: EdgeInsets.symmetric(horizontal: mobile ? 10 : 24, vertical: 16),
                      itemCount: reversed.length,
                      itemBuilder: (_, i) {
                        final m = reversed[i];
                        final older = i + 1 < reversed.length ? reversed[i + 1] : null;
                        final showDay = older == null || !DateUtils.isSameDay(older.createdAt, m.createdAt);
                        final replied = m.replyToId == null ? null : _messages.where((x) => x.id == m.replyToId).firstOrNull;
                        final showName = _isGroup && m.senderId != me && (older == null || older.senderId != m.senderId || showDay);
                        return Column(children: [
                          if (showDay) _DayDivider(m.createdAt),
                          _Bubble(
                            msg: m,
                            mine: m.senderId == me,
                            replied: replied,
                            senderName: showName ? (_senders[m.senderId]?.displayName ?? 'Member') : null,
                            reactions: _reactions[m.id] ?? const [],
                            myReaction: _myReactions[m.id],
                            onReply: () {
                              setState(() => _replyTo = m);
                              _focus.requestFocus();
                            },
                            onActions: () => _actions(m),
                            onToggleReaction: (e) => _react(m, _myReactions[m.id] == e ? null : e),
                          ),
                        ]);
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
    ]);

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
      child: Stack(children: [
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
                child: Center(child: Text('Drop files to send', style: TRText.display(22, context.tr.text1))),
              ),
            ),
          ),
      ]),
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
    return ChatWallpaper(path: _wallpaper, child: body);
  }
}

class _Header extends StatelessWidget {
  final String title, subtitle;
  final String? avatarUrl;
  final VoidCallback? onBack, onInfo, onTitle, onWallpaper, onZone;
  final void Function(String kind)? onCall;
  const _Header(
      {required this.title, required this.subtitle, this.avatarUrl, this.onBack, this.onInfo, this.onCall, this.onTitle, this.onWallpaper, this.onZone});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      padding: EdgeInsets.fromLTRB(onBack != null ? 4 : 20, MediaQuery.paddingOf(context).top + 10, 12, 10),
      decoration: BoxDecoration(color: c.surface1.withValues(alpha: .7), border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        if (onBack != null) TRIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back (Esc)', onPressed: onBack, size: 44),
        Expanded(
          child: Hoverable(
            onTap: onTitle,
            builder: (_, __) => Row(children: [
              TRAvatar(name: title, url: avatarUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TRText.body(16, c.text1, w: FontWeight.w700)),
                  Text(subtitle, style: TRText.body(12, c.text3)),
                ]),
              ),
            ]),
          ),
        ),
        TRIconButton(icon: Icons.call_outlined, tooltip: 'Voice call', onPressed: onCall == null ? null : () => onCall!('voice')),
        TRIconButton(icon: Icons.videocam_outlined, tooltip: 'Video call', onPressed: onCall == null ? null : () => onCall!('video')),
        TRIconButton(icon: Icons.headphones_rounded, tooltip: 'Zone', onPressed: onZone),
        TRIconButton(icon: Icons.wallpaper_rounded, tooltip: 'Wallpaper', onPressed: onWallpaper),
        if (onInfo != null) TRIconButton(icon: Icons.info_outline_rounded, tooltip: 'Chat info', onPressed: onInfo),
      ]),
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
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(TRRadius.pill), border: Border.all(color: c.border)),
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
  final Message? replied;
  final String? senderName;
  final List<String> reactions;
  final String? myReaction;
  final VoidCallback onReply, onActions;
  final void Function(String) onToggleReaction;
  const _Bubble({
    required this.msg,
    required this.mine,
    this.replied,
    this.senderName,
    required this.reactions,
    this.myReaction,
    required this.onReply,
    required this.onActions,
    required this.onToggleReaction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tr, a = context.accent;
    final sticker = !msg.deleted && isStickerName(msg.mediaName);
    final fg = sticker ? c.text1 : (mine ? TRAccent.on(a) : c.text1);
    final maxW = MediaQuery.sizeOf(context).width * (Responsive.isMobile(context) ? .78 : .5);
    final hasMedia = !msg.deleted && msg.mediaUrl != null;
    final text = msg.deleted ? 'This message was deleted' : msg.content;

    final counts = <String, int>{};
    for (final e in reactions) {
      counts[e] = (counts[e] ?? 0) + 1;
    }

    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (senderName != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(senderName!, style: TRText.body(12, a, w: FontWeight.w700)),
        ),
      if (replied != null && !msg.deleted)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(TRRadius.sm),
            border: Border(left: BorderSide(color: fg.withValues(alpha: .6), width: 3)),
          ),
          child: Text(_replyLabel(replied!), maxLines: 2, overflow: TextOverflow.ellipsis, style: TRText.body(12, fg.withValues(alpha: .8))),
        ),
      if (hasMedia) Padding(padding: EdgeInsets.only(bottom: text == null ? 0 : 6), child: Attachment(msg: msg, fg: fg)),
      if (text != null)
        SelectableText(text,
            style: TRText.body(15, msg.deleted ? fg.withValues(alpha: .6) : fg).copyWith(fontStyle: msg.deleted ? FontStyle.italic : null)),
      const SizedBox(height: 2),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (msg.edited && !msg.deleted) Text('edited · ', style: TRText.body(10, fg.withValues(alpha: .6))),
        Text(DateFormat.Hm().format(msg.createdAt), style: TRText.body(10, fg.withValues(alpha: .7))),
        if (mine) ...[
          const SizedBox(width: 4),
          Icon(msg.pending ? Icons.schedule_rounded : Icons.done_all_rounded, size: 13, color: fg.withValues(alpha: .75)),
        ],
      ]),
    ]);

    final box = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: sticker ? const EdgeInsets.all(2) : const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: sticker
          ? null
          : BoxDecoration(
              color: mine ? a : c.bubbleIn,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(TRRadius.x2l),
                topRight: const Radius.circular(TRRadius.x2l),
                bottomLeft: Radius.circular(mine ? TRRadius.x2l : 6),
                bottomRight: Radius.circular(mine ? 6 : TRRadius.x2l),
              ),
              boxShadow: TRShadow.md(Colors.black.withValues(alpha: .4)),
            ),
      child: content,
    );

    final bubble = Hoverable(
      builder: (_, h) => Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (mine && h && !msg.deleted) ...[
            TRIconButton(icon: Icons.more_horiz_rounded, tooltip: 'More', size: 30, onPressed: onActions),
            TRIconButton(icon: Icons.reply_rounded, tooltip: 'Reply', size: 30, onPressed: onReply),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(onLongPress: onActions, onSecondaryTap: onActions, child: box),
                if (counts.isNotEmpty && !msg.deleted)
                  Wrap(spacing: 4, children: [
                    for (final e in counts.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(TRRadius.pill),
                        onTap: () => onToggleReaction(e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: myReaction == e.key ? a.withValues(alpha: .25) : c.surface2,
                            borderRadius: BorderRadius.circular(TRRadius.pill),
                            border: Border.all(color: myReaction == e.key ? a : c.border),
                          ),
                          child: Text(e.value > 1 ? '${e.key} ${e.value}' : e.key, style: TRText.body(13, c.text1)),
                        ),
                      ),
                  ]),
              ],
            ),
          ),
          if (!mine && h && !msg.deleted) ...[
            TRIconButton(icon: Icons.reply_rounded, tooltip: 'Reply', size: 30, onPressed: onReply),
            TRIconButton(icon: Icons.more_horiz_rounded, tooltip: 'More', size: 30, onPressed: onActions),
          ],
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
        child: Padding(padding: const EdgeInsets.only(left: 12), child: Icon(Icons.reply_rounded, color: c.text2)),
      ),
      child: bubble,
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final Message? replyTo, editing;
  final bool recording, showStickers;
  final String uid;
  final VoidCallback onCancelReply, onSend, onAttach, onMic, onToggleStickers, onVoiceCancel;
  final void Function(String, Uint8List, String) onVoiceSend;
  final void Function(LocalSticker) onSticker;
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
  });

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final mobile = Responsive.isMobile(context);
    final banner = editing != null ? 'Editing message' : (replyTo != null ? 'Replying: ${_replyLabel(replyTo!)}' : null);
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: c.surface1.withValues(alpha: .8), border: Border(top: BorderSide(color: c.border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (showStickers && !recording) StickerPicker(uid: uid, onPick: onSticker),
        if (banner != null && !recording)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(TRRadius.lg),
              border: Border(left: BorderSide(color: context.accent, width: 3)),
            ),
            child: Row(children: [
              Icon(editing != null ? Icons.edit_outlined : Icons.reply_rounded, size: 16, color: c.text2),
              const SizedBox(width: 8),
              Expanded(child: Text(banner, maxLines: 1, overflow: TextOverflow.ellipsis, style: TRText.body(13, c.text2))),
              TRIconButton(icon: Icons.close_rounded, tooltip: 'Cancel (Esc)', size: 30, onPressed: onCancelReply),
            ]),
          ),
        if (recording)
          VoiceRecorderBar(onCancel: onVoiceCancel, onSend: onVoiceSend)
        else
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            TRIconButton(icon: Icons.add_rounded, tooltip: 'Attach', size: mobile ? 46 : 40, onPressed: onAttach),
            TRIconButton(
                icon: Icons.emoji_emotions_outlined,
                tooltip: 'Stickers',
                size: mobile ? 46 : 40,
                active: showStickers,
                onPressed: onToggleStickers),
            const SizedBox(width: 6),
            Expanded(
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.enter): onSend},
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: mobile ? TextInputAction.newline : TextInputAction.none,
                  style: TRText.body(15, c.text1),
                  cursorColor: context.accent,
                  decoration: InputDecoration(
                    hintText: 'Write a message…',
                    hintStyle: TRText.body(15, c.text3),
                    filled: true,
                    fillColor: c.surface2,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: mobile ? 14 : 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(TRRadius.x3l), borderSide: BorderSide(color: c.border)),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(TRRadius.x3l), borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(TRRadius.x3l), borderSide: BorderSide(color: context.accent)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Mic when empty, send when there is text (like the website).
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, __) {
                final empty = v.text.trim().isEmpty && editing == null;
                return Hoverable(
                  tooltip: empty ? 'Record voice note' : 'Send (Enter)',
                  onTap: empty ? onMic : onSend,
                  builder: (_, h) => AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: mobile ? 48 : 44,
                    height: mobile ? 48 : 44,
                    decoration: BoxDecoration(
                      color: context.accent,
                      shape: BoxShape.circle,
                      boxShadow: h ? TRShadow.glow(context.accent) : null,
                    ),
                    child: Icon(empty ? Icons.mic_rounded : (editing != null ? Icons.check_rounded : Icons.send_rounded),
                        size: 20, color: TRAccent.on(context.accent)),
                  ),
                );
              },
            ),
          ]),
      ]),
    );
  }
}
