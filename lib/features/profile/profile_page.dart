import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_scope.dart';
import '../../core/fancy.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../shell/app_shell.dart';

const appVersion = '0.5.0';

/// Profile + settings. Port of routes/app.profile.tsx and components/settings/settings-panel.tsx.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

const _sections = [
  ('profile', 'Profile', Icons.person_outline_rounded, ['name', 'bio', 'about', 'picture', 'avatar']),
  ('appearance', 'Appearance', Icons.palette_outlined, ['theme', 'dark', 'light', 'accent', 'colour', 'color', 'font', 'compact']),
  ('accessibility', 'Accessibility', Icons.visibility_outlined, ['motion', 'animation', 'text size']),
  ('privacy', 'Privacy', Icons.lock_outline_rounded, ['notification', 'preview', 'security']),
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
    final items = _sections.where((s) => q.isEmpty || s.$2.toLowerCase().contains(q) || s.$4.any((k) => k.contains(q))).toList();
    final current = _section ?? (mobile ? null : 'profile');

    final menu = ListView(padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + mobileBarClearance(context)), children: [
      Text('Account', style: TRText.display(26, c.text1)),
      const SizedBox(height: 16),
      _IdentityCard(onEdit: () => setState(() => _section = 'profile')),
      const SizedBox(height: 16),
      TRTextField(controller: _search, hint: 'Search settings', icon: Icons.search_rounded, onChanged: (_) => setState(() {})),
      const SizedBox(height: 10),
      for (final s in items)
        Hoverable(
          onTap: () => setState(() => _section = s.$1),
          builder: (_, h) => Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: current == s.$1 ? c.surface3 : (h ? c.text1.withValues(alpha: .05) : Colors.transparent),
              borderRadius: BorderRadius.circular(TRRadius.xl),
            ),
            child: Row(children: [
              Icon(s.$3, color: context.accent, size: 20),
              const SizedBox(width: 14),
              Expanded(child: Text(s.$2, style: TRText.body(15, c.text1))),
              Icon(Icons.chevron_right_rounded, color: c.text3),
            ]),
          ),
        ),
      if (items.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('No matching settings.', style: TRText.body(13, c.text3))),
      const Divider(height: 32),
      TRButton(label: 'Sign out', icon: Icons.logout_rounded, variant: TRButtonVariant.danger, onPressed: scope.auth.signOut),
    ]);

    Widget detail(String key) {
      final body = switch (key) {
        'profile' => const _ProfileEditor(),
        'appearance' => const _Appearance(),
        'accessibility' => const _Accessibility(),
        'privacy' => const _Privacy(),
        _ => const _About(),
      };
      final title = _sections.firstWhere((s) => s.$1 == key).$2;
      return ListView(padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + mobileBarClearance(context)), children: [
        Row(children: [
          if (mobile) TRIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back to account', onPressed: () => setState(() => _section = null)),
          if (mobile) const SizedBox(width: 6),
          Text(title, style: TRText.display(22, c.text1)),
        ]),
        const SizedBox(height: 18),
        body,
      ]);
    }

    return SafeArea(
      bottom: false,
      child: mobile
          ? (current == null ? menu : detail(current))
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 340, child: menu),
              VerticalDivider(width: 1, color: c.border),
              Expanded(child: Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: detail(current!)))),
            ]),
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.surface1, borderRadius: BorderRadius.circular(TRRadius.x3l), border: Border.all(color: c.border)),
          child: Row(children: [
            TRAvatar(name: plainName(p?.displayName ?? '?'), url: p?.avatarUrl, size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FancyText(p?.displayName ?? '', style: TRText.display(18, c.text1), maxLines: 1),
                Text('@${p?.username ?? ''}', style: TRText.mono(12, c.text2)),
                if (p?.isAdmin == true) Text('Admin', style: TRText.body(11, context.accent, w: FontWeight.w700)),
              ]),
            ),
            TRIconButton(icon: Icons.edit_outlined, tooltip: 'Edit profile', onPressed: onEdit),
          ]),
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
  _Style(this.fx, this.color);
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
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.firstOrNull;
    if (f?.bytes == null || !mounted) return;
    if (f!.size > 10 * 1024 * 1024) return showToast(context, 'Image must be under 10 MB.', error: true);
    setState(() => _uploading = true);
    try {
      final db = Supabase.instance.client;
      final ext = (f.extension ?? 'png').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final path = '$uid/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await db.storage.from('avatars').uploadBinary(path, f.bytes!,
          fileOptions: FileOptions(cacheControl: '3600', upsert: true, contentType: lookupMimeType(f.name, headerBytes: f.bytes) ?? 'image/png'));
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
    if (_name.text.trim().length < 2) return showToast(context, 'Display name must be at least 2 characters.', error: true);
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'display_name': encodeFancy(_name.text.trim(), _nameStyle.fx, _nameStyle.color),
        'bio': _bio.text.trim().isEmpty ? null : encodeFancy(_bio.text.trim(), _bioStyle.fx, _bioStyle.color),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label colour', style: TRText.body(12, c.text2, w: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final col in _nameColors)
          GestureDetector(
            onTap: () => setState(() => st.color = col),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: col ?? c.surface3,
                border: Border.all(color: st.color == col ? c.text1 : c.border, width: 2),
              ),
              child: col == null ? Icon(Icons.block_rounded, size: 14, color: c.text3) : null,
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Text('$label effect', style: TRText.body(12, c.text2, w: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: const Text('None'), selected: st.fx == null, onSelected: (_) => setState(() => st.fx = null)),
        for (final fx in motionFx) ChoiceChip(label: Text(motionLabels[fx]!), selected: st.fx == fx, onSelected: (_) => setState(() => st.fx = fx)),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final p = AppScope.of(context).auth.profile;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Stack(children: [
          TRAvatar(name: plainName(p?.displayName ?? '?'), url: p?.avatarUrl, size: 104),
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
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.photo_camera_outlined, size: 18, color: TRAccent.on(context.accent)),
                ),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Center(child: Text('@${p?.username ?? ''}', style: TRText.mono(12, c.text2))),
      const SizedBox(height: 20),
      Text('Display name', style: TRText.body(13, c.text2, w: FontWeight.w600)),
      const SizedBox(height: 6),
      TRTextField(controller: _name, hint: 'Your name', maxLength: 40, onChanged: (_) => setState(() {})),
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
        decoration: InputDecoration(hintText: 'A few words about you', filled: true, fillColor: c.surface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(TRRadius.xl))),
      ),
      _stylePicker('About', _bioStyle),
      const SizedBox(height: 20),
      Text('Preview', style: TRText.body(13, c.text2, w: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.surface1, borderRadius: BorderRadius.circular(TRRadius.x2l), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FancyText(encodeFancy(_name.text.isEmpty ? 'Your name' : _name.text, _nameStyle.fx, _nameStyle.color), style: TRText.display(18, c.text1)),
          if (_bio.text.isNotEmpty) FancyText(encodeFancy(_bio.text, _bioStyle.fx, _bioStyle.color), style: TRText.body(14, c.text2), maxLines: 5),
        ]),
      ),
      const SizedBox(height: 20),
      TRButton(label: _saving ? 'Saving…' : 'Save profile', loading: _saving, large: true, onPressed: _saving ? null : _save),
    ]);
  }
}

// ------------------------------------------------------------- settings sections

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card(this.children);
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: c.surface1, borderRadius: BorderRadius.circular(TRRadius.x2l), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TRText.body(14, c.text1)),
          if (hint != null) Text(hint!, style: TRText.body(12, c.text3)),
        ]),
        child,
      ]),
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
        Wrap(spacing: 8, children: [
          for (final s in TRAccent.swatches)
            GestureDetector(
              onTap: () => t.setAccent(s),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: s, shape: BoxShape.circle, border: Border.all(color: t.accent == s ? c.text1 : Colors.transparent, width: 2)),
              ),
            ),
        ]),
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
      _Row('Compact mode', Switch(value: t.compact, onChanged: t.setCompact), hint: 'Tighter spacing.'),
    ]);
  }
}

class _Accessibility extends StatelessWidget {
  const _Accessibility();
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    return _Card([
      _Row('Reduced motion', Switch(value: t.reducedMotion, onChanged: t.setReducedMotion), hint: 'Stops animated names and most animations.'),
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
    return _Card([
      _Row('Hide notification previews', Switch(value: t.hidePreviews, onChanged: t.setHidePreviews),
          hint: 'Notifications will say "New message" instead of the text.'),
    ]);
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
