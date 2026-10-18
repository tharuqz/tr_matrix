import '../../core/desktop_menu.dart';
import 'package:flutter/material.dart';
import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/chat_appearance.dart';
import '../../core/theme/chat_pattern.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import 'chat_theme_sheet_tabs_a.dart';
import 'chat_theme_sheet_tabs_b.dart';
import 'wallpaper.dart';

class ChatThemeSheet extends StatefulWidget {
  final String chatId;
  final bool wallpaperTab;
  final void Function(String?)? onWallpaper;
  const ChatThemeSheet(
      {super.key,
      required this.chatId,
      this.wallpaperTab = false,
      this.onWallpaper});
  static Future<void> show(BuildContext c, String chatId,
          {bool wallpaperTab = false, void Function(String?)? onWallpaper}) =>
      showAnchoredSheet<void>(
        large: true,
        context: c,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (ctx) => useDesktopMenus(ctx)
            ? ChatThemeSheet(
                chatId: chatId,
                wallpaperTab: wallpaperTab,
                onWallpaper: onWallpaper)
            : DraggableScrollableSheet(
          initialChildSize: 0.92,
          maxChildSize: 0.96,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => ChatThemeSheet(
              chatId: chatId,
              wallpaperTab: wallpaperTab,
              onWallpaper: onWallpaper),
        ),
      );
  @override
  State<ChatThemeSheet> createState() => _ChatThemeSheetState();
}

class _ChatThemeSheetState extends State<ChatThemeSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  ChatAppearanceStore? _store;
  String? _uid;
  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 5, vsync: this, initialIndex: widget.wallpaperTab ? 0 : 1);
  }

  @override
  void dispose() {
    _tab.dispose();
    _store?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nuid = AppScope.of(context).auth.user?.id ?? 'anon';
    if (_uid == nuid && _store != null) return;
    _uid = nuid;
    _store?.dispose();
    _store = ChatAppearanceStore(nuid, widget.chatId)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final ap = _store?.value ?? defaultAppearance;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(TRRadius.glass),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          if (!useDesktopMenus(context))
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Chat theme', style: TRText.display(18, c.text1)),
                ),
                TextButton(
                  onPressed: () async {
                    await _store?.reset();
                  },
                  child: Text('Reset', style: TRText.body(13, context.accent)),
                ),
                TRIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          _Preview(ap: ap),
          TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: context.accent,
            unselectedLabelColor: c.text2,
            indicatorColor: context.accent,
            tabs: const [
              Tab(text: 'Wallpaper'),
              Tab(text: 'Background'),
              Tab(text: 'Bubbles'),
              Tab(text: 'Composer'),
              Tab(text: 'Pattern'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                WallpaperPanel(
                    chatId: widget.chatId,
                    onChanged: (p) => widget.onWallpaper?.call(p)),
                BgTab(ap: ap, onPatch: (m) => _store?.patch(m)),
                BubblesTab(ap: ap, onPatch: (m) => _store?.patch(m)),
                ComposerTab(ap: ap, onPatch: (m) => _store?.patch(m)),
                PatternTab(ap: ap, onPatch: (m) => _store?.patch(m)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final ChatAppearance ap;
  const _Preview({required this.ap});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final bg = ap.background == 'preset' ? chatPresetGradient(ap.preset) : null;
    return Container(
      height: 168,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TRRadius.xl),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: bg != null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: bg,
                      ),
                    ),
                  )
                : Container(color: c.surface2),
          ),
          Positioned.fill(
            child: Container(color: c.bg.withValues(alpha: ap.dim / 100)),
          ),
          Positioned.fill(
            child: ChatPatternLayer(ap: ap, accent: context.accent),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _hexOr(
                        ap.color,
                        context.accent,
                      ).withValues(alpha: ap.visibility / 100),
                      borderRadius:
                          BorderRadius.circular(chatBubbleRadius(ap)),
                    ),
                    child: Text(
                      'Hey — TR MATRIX',
                      style: TRText.body(13, Colors.white, w: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: ap.receivedColor == 'auto'
                          ? c.surface1
                          : (parseHex(ap.receivedColor) ?? c.surface1)
                              .withValues(alpha: ap.receivedVisibility / 100),
                      borderRadius:
                          BorderRadius.circular(chatBubbleRadius(ap)),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      'Bubble preview',
                      style: TRText.body(13, c.text1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: composerEffectiveColor(
                      ap,
                      c,
                    ).withValues(alpha: composerStrength(ap)),
                    borderRadius: BorderRadius.circular(composerRadius(ap)),
                    border: composerBorder(ap, c) != null
                        ? Border.all(color: composerBorder(ap, c)!)
                        : null,
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

Color _hexOr(String s, Color fb) {
  try {
    if (!s.startsWith('#')) return fb;
    return Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return fb;
  }
}

Color? parseHex(String s) {
  try {
    return Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return null;
  }
}
