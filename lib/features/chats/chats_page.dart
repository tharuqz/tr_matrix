import '../../core/desktop_menu.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import 'chat_info_panel.dart';
import 'chat_list_pane.dart';
import 'chat_view.dart';
import '../calls/start_call.dart';
import '../../core/motion.dart';

/// Messages section.
/// Desktop/tablet: chat list | active chat | (optional) info/call panel — like the reference screenshot.
/// Mobile: list only; tapping opens a full-screen chat route.
class ChatsPage extends StatefulWidget {
  final String? chatId;
  final ChatItem? initial;
  const ChatsPage({super.key, this.chatId, this.initial});
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  ChatItem? _selected;
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  void _open(ChatItem item) {
    setState(() {
      _selected = item;
      _showInfo = false;
    });
    context.go('/app/chat/${item.id}', extra: item);
  }

  @override
  void didUpdateWidget(covariant ChatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _selected = widget.initial;
      _showInfo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final mobile = Responsive.isMobile(context);
    final chatId = widget.chatId;
    final sel = _selected?.id == chatId ? _selected : widget.initial;

    if (mobile) {
      if (chatId == null)
        return SafeArea(bottom: false, child: ChatListPane(onOpen: _open));
      return ChatView(
        chatId: chatId,
        title: sel?.title ?? 'Chat',
        avatarUrl: sel?.avatarUrl,
        onBack: () => context.go('/app'),
        onCall: (k) => startCallForChat(context, chatId, sel, k),
        onToggleInfo: () => showAnchoredSheet(
        large: true,
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .9,
            maxChildSize: .96,
            builder: (_, sc) => ChatInfoPanel(item: sel, scrollController: sc),
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 1200;
    return Row(
      children: [
        Container(
          width: MediaQuery.sizeOf(context).width < 1000 ? 280 : 330,
          decoration: BoxDecoration(
            color: c.bg,
            border: Border(right: BorderSide(color: c.border)),
          ),
          child: ChatListPane(selectedId: chatId, onOpen: _open),
        ),
        Expanded(
          child: chatId == null
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Select a chat',
                  subtitle: 'Your conversations, connected.',
                )
              : ChatView(
                  key: ValueKey(chatId),
                  chatId: chatId,
                  title: sel?.title ?? 'Chat',
                  avatarUrl: sel?.avatarUrl,
                  onBack: () => context.go('/app'),
                  onCall: (k) => startCallForChat(context, chatId, sel, k),
                  onToggleInfo: () => setState(() => _showInfo = !_showInfo),
                ),
        ),
        AnimatedSize(
          duration: matrixDuration(context),
          curve: Curves.easeOutCubic,
          child: chatId != null && wide && _showInfo
              ? Container(
                  width: 320,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: c.border)),
                  ),
                  child: ChatInfoPanel(item: sel),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
