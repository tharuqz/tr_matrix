import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_scope.dart';
import '../../core/motion.dart';
import '../../core/fancy.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/avatar_crop_dialog.dart';
import '../settings/devices_section.dart';
import '../../core/security/app_lock.dart';
import '../security/lock_screen.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';

const appVersion = '0.5.2';

/// Profile + settings. Port of routes/app.profile.tsx and components/settings/settings-panel.tsx.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

const _sections = [
  (
    'profile',
    'Profile',
    Icons.person_outline_rounded,
    ['name', 'bio', 'about', 'picture', 'avatar'],
  ),
  (
    'appearance',
    'Appearance',
    Icons.palette_outlined,
    ['theme', 'dark', 'light', 'accent', 'colour', 'color', 'font', 'compact'],
  ),
  (
    'accessibility',
    'Accessibility',
    Icons.visibility_outlined,
    ['motion', 'animation', 'text size'],
  ),
  (
    'privacy',
    'Privacy',
    Icons.lock_outline_rounded,
    ['notification', 'preview', 'security', 'lock', 'pin', 'fingerprint'],
  ),
  ('about', 'About', Icons.info_outline_rounded, ['version', 'app']),
];

class _ProfilePageState extends State<ProfilePage> {
  String? _section; // null = menu on phones
  final _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final scope = AppScope.of(context);
    final mobile = Responsive.isMobile(context);
    final q = _search.text.trim().toLowerCase();
    final items = _sections
        .where(
          (s) =>
              q.isEmpty ||
              s.$2.toLowerCase().contains(q) ||
              s.$4.any((k) => k.contains(q)),
        )
        .toList();
    final current = _section ?? (mobile ? null : 'profile');

    final menu = ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        20,
        16,
        24 + mobileBarClearance(context),
      ),
      children: [
        Text('Settings', style: TRText.display(24, c.text1)),
        const SizedBox(height: 12),
        _IdentityCard(onEdit: () => setState(() => _section = 'profile')),
        const SizedBox(height: 16),
        TRTextField(
          controller: _search,
          hint: 'Search settings',
          icon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        for (final s in items)
          Hoverable(
            onTap: () => setState(() => _section = s.$1),
            builder: (_, h) => Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: current == s.$1
                    ? context.accent.withValues(alpha: .12)
                    : (h ? c.text1.withValues(alpha: .05) : Colors.transparent),
                borderRadius: BorderRadius.circular(TRRadius.xl),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(s.$3, color: context.accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.$2, style: TRText.body(15, c.text1))),
                  if (mobile)
                    Icon(Icons.chevron_right_rounded, color: c.text3),
                ],
              ),
            ),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No matching settings.',
              style: TRText.body(13, c.text3),
            ),
          ),
        const Divider(height: 32),
        TRButton(
          label: 'Sign out',
          icon: Icons.logout_rounded,
          variant: TRButtonVariant.danger,
          onPressed: scope.auth.signOut,
        ),
      ],
    );

    Widget detail(String key) {
      final body = switch (key) {
        'profile' => const _ProfileEditor(),
        'appearance' => const _Appearance(),
        'accessibility' => const _Accessibility(),
        'privacy' => const _Privacy(),
        _ => const _About(),
      };
      final title = _sections.firstWhere((s) => s.$1 == key).$2;
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + mobileBarClearance(context),
        ),
        children: [
          Row(
            children: [
              if (mobile)
                TRIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back to account',
                  onPressed: () => setState(() => _section = null),
                ),
              if (mobile) const SizedBox(width: 6),
              Text(title, style: TRText.display(22, c.text1)),
            ],
          ),
          const SizedBox(height: 18),
          MatrixReveal(key: ValueKey(key), child: body),
        ],
      );
    }

    return SafeArea(
      bottom: false,
      child: mobile
          ? (current == null ? menu : detail(current))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 300, child: menu),
                VerticalDivider(width: 1, color: c.border),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: detail(current!),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final VoidCallback onEdit;
  const _IdentityCard({required this.onEdit});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (_, __) {
        final p = auth.profile;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              TRAvatar(
                name: plainName(p?.displayName ?? '?'),
                url: p?.avatarUrl,
                size: 60,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FancyText(
                      p?.displayName ?? '',
                      style: TRText.display(18, c.text1),
                      maxLines: 1,
                    ),
                    Text(
                      '@${p?.username ?? ''}',
                      style: TRText.mono(12, c.text2),
                    ),
                    if (p?.isAdmin == true)
                      Text(
                        'Admin',
                        style: TRText.body(
                          11,
                          context.accent,
                          w: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              TRIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit profile',
                onPressed: onEdit,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------- profile editor

const _nameColors = [
  null,
  Color(0xFF22D3EE),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFFEF4444),
  Color(0xFFFFFFFF),
];

class _Style {
  String? fx;
  Color? color;
  String font = 'normal';
  _Style(this.fx, this.color);
  String apply(String t) => encodeFancy(applyFont(t, font), fx, color);
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor();
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _name = TextEditingController(), _bio = TextEditingController();
  late _Style _nameStyle, _bioStyle;
  bool _saving = false, _uploading = false, _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final p = AppScope.of(context).auth.profile;
    final n = decodeFancy(p?.displayName ?? ''), b = decodeFancy(p?.bio ?? '');
    _name.text = n.text;
    _bio.text = b.text;
    _nameStyle = _Style(n.fx, n.color);
    _bioStyle = _Style(b.fx, b.color);
    _ready = true;
  }

  Future<void> _pickAvatar() async {
    final scope = AppScope.of(context);
    final uid = scope.auth.user?.id;
    if (uid == null) return;
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final f = r?.files.firstOrNull;
    if (f?.bytes == null || !mounted) return;
    if (f!.size > 10 * 1024 * 1024)
      return showToast(context, 'Image must be under 10 MB.', error: true);
    Uint8List bytes = f.bytes!;
    // avatar-crop parity: show crop dialog before upload (512x512 JPEG)
    if (mounted) {
      bool cropped = false;
      Uint8List? out;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AvatarCropDialog(
          bytes: bytes,
          name: f.name,
          onConfirm: (jpeg) async {
            out = jpeg;
            cropped = true;
          },
          onCancel: () => Navigator.pop(context),
        ),
      );
      if (!cropped || out == null) return;
      bytes = out!;
    }
    setState(() => _uploading = true);
    try {
      final db = Supabase.instance.client;
      final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await db.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      await db.from('profiles').update({'avatar_url': path}).eq('id', uid);
      await scope.auth.refreshProfile();
      if (mounted) showToast(context, 'Profile picture updated.');
    } catch (e) {
      if (mounted) showToast(context, 'Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final scope = AppScope.of(context);
    final uid = scope.auth.user?.id;
    if (uid == null) return;
    if (_name.text.trim().length < 2)
      return showToast(
        context,
        'Display name must be at least 2 characters.',
        error: true,
      );
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'display_name': _nameStyle.apply(_name.text.trim()),
        'bio':
            _bio.text.trim().isEmpty ? null : _bioStyle.apply(_bio.text.trim()),
      }).eq('id', uid);
      await scope.auth.refreshProfile();
      if (mounted) showToast(context, 'Profile saved.');
    } catch (e) {
      if (mounted) showToast(context, 'Save failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stylePicker(String label, _Style st) {
    final c = context.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label colour',
          style: TRText.body(11, c.text3, w: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: Text(
                'Auto',
                style: TRText.body(
                  12,
                  st.color == null ? TRAccent.on(context.accent) : c.text1,
                ),
              ),
              selected: st.color == null,
              onSelected: (_) => setState(() => st.color = null),
              backgroundColor: c.surface2,
              selectedColor: context.accent,
              side: BorderSide(color: c.border),
              shape: const StadiumBorder(),
            ),
            for (final col in _nameColors.where((x) => x != null).cast<Color>())
              GestureDetector(
                onTap: () => setState(() => st.color = col),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: col,
                    border: Border.all(
                      color: st.color == col ? context.accent : c.border,
                      width: st.color == col ? 2 : 1,
                    ),
                    boxShadow: st.color == col
                        ? [
                            BoxShadow(
                              color: context.accent.withValues(alpha: .5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: col == null
                      ? Icon(Icons.block_rounded, size: 14, color: c.text3)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '$label effect',
          style: TRText.body(12, c.text2, w: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: Text(
                'None',
                style: TRText.body(
                  12,
                  st.fx == null ? TRAccent.on(context.accent) : c.text1,
                ),
              ),
              selected: st.fx == null,
              onSelected: (_) => setState(() => st.fx = null),
              backgroundColor: c.surface2,
              selectedColor: context.accent,
              side: BorderSide.none,
              shape: const StadiumBorder(),
            ),
            for (final fx in motionFx)
              ChoiceChip(
                label: Text(
                  motionLabels[fx]!,
                  style: TRText.body(
                    12,
                    st.fx == fx ? TRAccent.on(context.accent) : c.text1,
                  ),
                ),
                selected: st.fx == fx,
                onSelected: (_) => setState(() => st.fx = fx),
                backgroundColor: c.surface2,
                selectedColor: context.accent,
                side: st.fx == fx
                    ? BorderSide(color: context.accent.withValues(alpha: .5))
                    : BorderSide.none,
                shape: const StadiumBorder(),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '$label font',
          style: TRText.body(12, c.text2, w: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in fancyFonts)
              ChoiceChip(
                label: Text(
                  applyFont(fontLabels[f]!, f),
                  style: TRText.body(
                    12,
                    st.font == f ? TRAccent.on(context.accent) : c.text1,
                  ),
                ),
                selected: st.font == f,
                onSelected: (_) => setState(() => st.font = f),
                backgroundColor: c.surface2,
                selectedColor: context.accent,
                side: st.font == f
                    ? BorderSide(color: context.accent.withValues(alpha: .5))
                    : BorderSide.none,
                shape: const StadiumBorder(),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final p = AppScope.of(context).auth.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Stack(
            children: [
              TRAvatar(
                name: plainName(p?.displayName ?? '?'),
                url: p?.avatarUrl,
                size: 104,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: context.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploading ? null : _pickAvatar,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                              color: TRAccent.on(context.accent),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('@${p?.username ?? ''}', style: TRText.mono(12, c.text2)),
        ),
        const SizedBox(height: 20),
        Text(
          'Display name',
          style: TRText.body(13, c.text2, w: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TRTextField(
          controller: _name,
          hint: 'Your name',
          maxLength: 40,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        _stylePicker('Name', _nameStyle),
        const SizedBox(height: 20),
        Text('About', style: TRText.body(13, c.text2, w: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _bio,
          minLines: 2,
          maxLines: 5,
          maxLength: 300,
          onChanged: (_) => setState(() {}),
          style: TRText.body(15, c.text1),
          decoration: InputDecoration(
            hintText: 'A few words about you',
            filled: true,
            fillColor: c.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TRRadius.xl),
            ),
          ),
        ),
        _stylePicker('About', _bioStyle),
        const SizedBox(height: 20),
        Text('Preview', style: TRText.body(13, c.text2, w: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FancyText(
                _nameStyle.apply(_name.text.isEmpty ? 'Your name' : _name.text),
                style: TRText.display(18, c.text1),
              ),
              if (_bio.text.isNotEmpty)
                FancyText(
                  _bioStyle.apply(_bio.text),
                  style: TRText.body(14, c.text2),
                  maxLines: 5,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TRButton(
          label: _saving ? 'Saving…' : 'Save profile',
          loading: _saving,
          large: true,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- settings sections

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card(this.children);
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
            height: 1, thickness: 1, color: c.border.withValues(alpha: .5)));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  const _Row(this.label, this.child, {this.hint});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (_, box) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TRText.body(14, c.text1, w: FontWeight.w500)),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!, style: TRText.body(12, c.text3)),
            ],
          ],
        );
                // Only small toggles sit beside the label; bigger pickers go below.
        if (child is! Switch || box.maxWidth < 280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 8), child],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            child,
          ],
        );
      }),
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance();
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final t = AppScope.of(context).theme;
    final modeValue = t.followSystem ? 'system' : t.mode.name;
    return _Card([
      _Row(
        'Theme',
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'dark', label: Text('Dark')),
            ButtonSegment(value: 'amoled', label: Text('AMOLED')),
            ButtonSegment(value: 'light', label: Text('Light')),
            ButtonSegment(value: 'system', label: Text('System')),
          ],
          selected: {modeValue},
          onSelectionChanged: (s) {
            final v = s.first;
            if (v == 'system') {
              t.setFollowSystem(true);
            } else {
              t.setMode(TRThemeMode.values.byName(v));
            }
          },
        ),
      ),
      _Row(
        'Accent',
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in TRAccent.swatches)
              GestureDetector(
                onTap: () => t.setAccent(s),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: s,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: t.accent == s ? context.accent : c.border,
                      width: t.accent == s ? 2 : 1,
                    ),
                    boxShadow: t.accent == s
                        ? [
                            BoxShadow(
                              color: context.accent.withValues(alpha: .5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      _Row(
        'Font size',
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'small', label: Text('Small')),
            ButtonSegment(value: 'medium', label: Text('Medium')),
            ButtonSegment(value: 'large', label: Text('Large')),
          ],
          selected: {t.fontSize},
          onSelectionChanged: (s) => t.setFontSize(s.first),
        ),
      ),
      _Row(
        'Compact mode',
        Switch(value: t.compact, onChanged: t.setCompact),
        hint: 'Tighter spacing.',
      ),
    ]);
  }
}

class _Accessibility extends StatelessWidget {
  const _Accessibility();
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    return _Card([
      _Row(
        'Reduced motion',
        Switch(value: t.reducedMotion, onChanged: t.setReducedMotion),
        hint: 'Stops animated names and most animations.',
      ),
      _Row(
        'Text size',
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'small', label: Text('A-')),
            ButtonSegment(value: 'medium', label: Text('A')),
            ButtonSegment(value: 'large', label: Text('A+')),
          ],
          selected: {t.fontSize},
          onSelectionChanged: (s) => t.setFontSize(s.first),
        ),
      ),
    ]);
  }
}

class _Privacy extends StatelessWidget {
  const _Privacy();
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    return Column(
      children: [
        _Card([
          _Row(
            'Hide notification previews',
            Switch(value: t.hidePreviews, onChanged: t.setHidePreviews),
            hint: 'Notifications will say "New message" instead of the text.',
          ),
        ]),
        const SizedBox(height: 16),
        const _AppLockCard(),
        const SizedBox(height: 16),
        const _Card([_Row('Active devices', DevicesSection())]),
      ],
    );
  }
}

class _About extends StatelessWidget {
  const _About();
  @override
  Widget build(BuildContext context) {
    return const _Card([
      _Row('App', Text('TR MATRIX')),
      _Row('Version', Text(appVersion)),
    ]);
  }
}

class _AppLockCard extends StatelessWidget {
  const _AppLockCard();
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return ListenableBuilder(
      listenable: AppLock.instance,
      builder: (context, _) {
        final l = AppLock.instance;
        const times = [
          (0, 'Immediately'),
          (1, 'After 1 min'),
          (5, 'After 5 min'),
          (15, 'After 15 min'),
          (60, 'After 1 hour'),
        ];
        return _Card([
          _Row(
            'App lock',
            Switch(
              value: l.enabled,
              onChanged: (on) async {
                if (on) {
                  if (await showSetPinDialog(context) && context.mounted)
                    showToast(context, 'App lock is on');
                } else if (await confirmUnlock(
                  context,
                  title: 'Turn off app lock',
                )) {
                  await l.disable();
                  if (context.mounted) showToast(context, 'App lock is off');
                }
              },
            ),
            hint:
                'Ask for a PIN every time TR MATRIX opens. Saved on this device only.',
          ),
          if (l.enabled) ...[
            _Row(
              'Lock after',
              DropdownButton<int>(
                value:
                    times.any((t) => t.$1 == l.timeoutMin) ? l.timeoutMin : 0,
                underline: const SizedBox.shrink(),
                dropdownColor: c.surface1,
                items: [
                  for (final t in times)
                    DropdownMenuItem(
                      value: t.$1,
                      child: Text(t.$2, style: TRText.body(13, c.text1)),
                    ),
                ],
                onChanged: (v) => l.setTimeout(v ?? 0),
              ),
            ),
            if (l.biometricAvailable)
              _Row(
                'Unlock with fingerprint',
                Switch(
                  value: l.biometricSetting,
                  onChanged: (on) async {
                    final ok = await l.setBiometric(on);
                    if (!ok && on && context.mounted)
                      showToast(
                        context,
                        'Fingerprint not confirmed',
                        error: true,
                      );
                  },
                ),
                hint:
                    'Optional. Use your fingerprint (or Windows Hello) instead of typing the PIN.',
              )
            else
              _Row(
                'Fingerprint',
                Text(
                  'Not available on this device',
                  style: TRText.body(12, c.text3),
                ),
              ),
            _Row(
              'Change PIN',
              TextButton(
                onPressed: () async {
                  if (await confirmUnlock(
                        context,
                        title: 'Enter current PIN',
                      ) &&
                      context.mounted) {
                    if (await showSetPinDialog(context) && context.mounted)
                      showToast(context, 'PIN changed');
                  }
                },
                child: const Text('Change'),
              ),
            ),
            _Row(
              'Lock now',
              TextButton(onPressed: l.lockNow, child: const Text('Lock')),
            ),
          ],
          _Row(
            'Locked chats',
            Text('${l.lockedChats.length}', style: TRText.body(13, c.text2)),
            hint:
                'Long-press a chat and choose "Lock & hide chat". Locked chats open only with your PIN or fingerprint.',
          ),
        ]);
      },
    );
  }
}
