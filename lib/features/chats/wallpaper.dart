import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'chat_theme_sheet.dart';
import 'package:mime/mime.dart';
import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_actions.dart';
import '../../widgets/common.dart';

/// Same preset ids as the website ("preset:aurora" etc.), drawn as still gradients.
const wallpaperPresets = <String, (String, List<Color>)>{
  'aurora': (
    'Aurora',
    [
      Color(0xFF0B1E3A),
      Color(0xFF1F3A8A),
      Color(0xFF3A1F8A),
      Color(0xFF0B1E3A),
    ],
  ),
  'liquid': (
    'Liquid',
    [Color(0xFF1E3A8A), Color(0xFF0B0B14), Color(0xFF6D28D9)],
  ),
  'nebula': (
    'Nebula',
    [
      Color(0xFF0B0B14),
      Color(0xFF1E1B4B),
      Color(0xFF4C1D95),
      Color(0xFF0B0B14),
    ],
  ),
  'waves': ('Waves', [Color(0xFF0A1A2B), Color(0xFF0F2746), Color(0xFF0A1A2B)]),
  'breathe': ('Breathe', [Color(0xFF312E81), Color(0xFF0B0B14)]),
};

/// Background layer behind the messages.
class ChatWallpaper extends StatelessWidget {
  final String? path;
  final Widget child;
  const ChatWallpaper({super.key, required this.path, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final p = path;
    Widget bg;
    if (p != null &&
        p.startsWith('preset:') &&
        wallpaperPresets.containsKey(p.substring(7))) {
      bg = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: wallpaperPresets[p.substring(7)]!.$2,
          ),
        ),
      );
    } else if (p != null && p.isNotEmpty) {
      bg = FutureBuilder<String?>(
        future: AppScope.of(context).chats.wallpaperUrl(p),
        builder: (_, s) => s.data == null
            ? const SizedBox.expand()
            : Image.network(
                s.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.expand(),
              ),
      );
    } else {
      return Container(color: c.bg.withValues(alpha: .55), child: child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        Container(color: c.bg.withValues(alpha: .45)),
        child,
      ],
    );
  }
}

/// Latest wallpaper change (chat id, path) so an open chat updates at once.
final wallpaperChanges = ValueNotifier<(String, String?)?>(null);

/// Opens the chat theme page on its Wallpaper tab.
Future<void> showWallpaperPicker(
  BuildContext context,
  String chatId,
  void Function(String?) onChanged,
) =>
    ChatThemeSheet.show(context, chatId,
        wallpaperTab: true, onWallpaper: onChanged);

/// Wallpaper choices (shared with everyone in the chat), shown inside the
/// chat theme page.
class WallpaperPanel extends StatelessWidget {
  final String chatId;
  final void Function(String?) onChanged;
  const WallpaperPanel(
      {super.key, required this.chatId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).chats;
    final c = context.tr;
    Future<void> apply(String? path) async {
      try {
        await repo.setWallpaper(chatId, path);
        wallpaperChanges.value = (chatId, path);
        onChanged(path);
        if (context.mounted)
          showToast(context,
              path == null ? 'Wallpaper removed' : 'Wallpaper updated');
      } catch (e) {
        if (context.mounted)
          showToast(context, 'Could not change wallpaper', error: true);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Chat wallpaper',
            style: TRText.body(15, c.text1, w: FontWeight.w700)),
        Text('Everyone in this chat sees the same wallpaper.',
            style: TRText.body(13, c.text3)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in wallpaperPresets.entries)
              InkWell(
                onTap: () => apply('preset:${e.key}'),
                borderRadius: BorderRadius.circular(TRRadius.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(TRRadius.lg),
                        border: Border.all(color: c.border),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: e.value.$2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(e.value.$1, style: TRText.body(12, c.text2)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            TRButton(
              label: 'Upload picture',
              icon: Icons.image_outlined,
              onPressed: () async {
                final r = await FilePicker.platform
                    .pickFiles(type: FileType.image, withData: true);
                final f = r?.files.firstOrNull;
                if (f?.bytes == null) return;
                if (f!.size > 4 * 1024 * 1024) {
                  if (context.mounted)
                    showToast(context, 'Wallpaper must be 4 MB or smaller',
                        error: true);
                  return;
                }
                try {
                  final path = await repo.uploadWallpaper(
                    chatId,
                    f.name,
                    f.bytes!,
                    lookupMimeType(f.name, headerBytes: f.bytes) ??
                        'image/jpeg',
                  );
                  await apply(path);
                } catch (_) {
                  if (context.mounted)
                    showToast(context, 'Upload failed', error: true);
                }
              },
            ),
            TRButton(
                label: 'Remove wallpaper',
                variant: TRButtonVariant.outline,
                onPressed: () => apply(null)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
            'A wallpaper shows instead of the Background chosen in the next tab.',
            style: TRText.body(12, c.text3)),
      ],
    );
  }
}
