import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/chat_actions.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';

Future<T?> _panel<T>(BuildContext context, Widget child) => showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ctx.tr.surface1,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TRRadius.glass),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
          child: child,
        ),
      ),
    );

/// Pick friends (used for new group and "add members").
class _FriendPicker extends StatefulWidget {
  final String title, action;
  final Set<String> exclude;
  final bool askName;
  final Future<void> Function(String name, List<String> ids) onDone;
  const _FriendPicker({
    required this.title,
    required this.action,
    this.exclude = const {},
    this.askName = false,
    required this.onDone,
  });
  @override
  State<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<_FriendPicker> {
  final _name = TextEditingController();
  List<Profile> _friends = [];
  final _picked = <String>{};
  bool _loading = true, _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading) return;
    AppScope.of(context).contacts.load().then((r) {
      if (mounted) {
        setState(() {
          _friends = r.friends
              .map((f) => f.profile)
              .where((p) => !widget.exclude.contains(p.id))
              .toList();
          _loading = false;
        });
      }
    });
  }

  Future<void> _submit() async {
    if (widget.askName && _name.text.trim().isEmpty)
      return showToast(context, 'Give the group a name', error: true);
    if (_picked.isEmpty)
      return showToast(context, 'Pick at least one friend', error: true);
    setState(() => _busy = true);
    try {
      await widget.onDone(_name.text.trim(), _picked.toList());
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        showToast(context, 'Something went wrong. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: TRText.display(20, c.text1)),
          const SizedBox(height: 14),
          if (widget.askName) ...[
            TRTextField(
              controller: _name,
              hint: 'Group name',
              icon: Icons.group_rounded,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _friends.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline,
                        title: 'No friends to add',
                      )
                    : ListView(
                        children: [
                          for (final p in _friends)
                            CheckboxListTile(
                              value: _picked.contains(p.id),
                              activeColor: context.accent,
                              onChanged: (v) => setState(
                                () => v == true
                                    ? _picked.add(p.id)
                                    : _picked.remove(p.id),
                              ),
                              secondary: TRAvatar(
                                name: p.displayName,
                                url: p.avatarUrl,
                                size: 36,
                              ),
                              title: Text(
                                p.displayName,
                                style: TRText.body(14, c.text1),
                              ),
                              subtitle: Text(
                                '@${p.username}',
                                style: TRText.body(12, c.text3),
                              ),
                            ),
                        ],
                      ),
          ),
          const SizedBox(height: 12),
          TRButton(
            label: '${widget.action} (${_picked.length})',
            loading: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

Future<void> showNewGroupDialog(BuildContext context) => _panel(
      context,
      _FriendPicker(
        title: 'New group',
        action: 'Create group',
        askName: true,
        onDone: (name, ids) async {
          final id = await AppScope.of(context).chats.createGroup(name, ids);
          if (context.mounted) context.go('/app/chat/$id');
        },
      ),
    );

/// Group info: rename, members, add/remove (admins), leave.
Future<void> showGroupInfo(
  BuildContext context,
  String chatId, {
  VoidCallback? onChanged,
}) =>
    _panel(context, _GroupInfo(chatId: chatId, onChanged: onChanged));

class _GroupInfo extends StatefulWidget {
  final String chatId;
  final VoidCallback? onChanged;
  const _GroupInfo({required this.chatId, this.onChanged});
  @override
  State<_GroupInfo> createState() => _GroupInfoState();
}

class _GroupInfoState extends State<_GroupInfo> {
  final _title = TextEditingController();
  List<GroupMember> _members = [];
  String? _avatar;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).chats;
    final row = await repo.chatRow(widget.chatId);
    final m = await repo.groupMembers(widget.chatId);
    if (!mounted) return;
    setState(() {
      _title.text = (row?['title'] ?? '') as String;
      _avatar = row?['avatar_url'] as String?;
      _members = m;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      widget.onChanged?.call();
      if (mounted) showToast(context, ok);
      await _load();
    } catch (_) {
      if (mounted)
        showToast(context, 'Only group admins can do that', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final repo = AppScope.of(context).chats;
    final me = repo.me;
    final iAmAdmin = _members.any((m) => m.profile.id == me && m.admin);
    if (_loading)
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    return ListView(
      padding: const EdgeInsets.all(20),
      shrinkWrap: true,
      children: [
        Center(
          child: TRAvatar(name: _title.text, url: _avatar, size: 72),
        ),
        const SizedBox(height: 14),
        if (iAmAdmin)
          Row(
            children: [
              Expanded(
                child: TRTextField(
                  controller: _title,
                  hint: 'Group name',
                  icon: Icons.edit_outlined,
                ),
              ),
              const SizedBox(width: 8),
              TRButton(
                label: 'Save',
                onPressed: () => _run(
                  () => repo.updateGroup(
                    widget.chatId,
                    _title.text.trim(),
                    _avatar,
                  ),
                  'Saved',
                ),
              ),
            ],
          )
        else
          Text(
            _title.text,
            textAlign: TextAlign.center,
            style: TRText.display(20, c.text1),
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_members.length} members',
                style: TRText.body(13, c.text2, w: FontWeight.w600),
              ),
            ),
            if (iAmAdmin)
              TextButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add'),
                onPressed: () => _panel(
                  context,
                  _FriendPicker(
                    title: 'Add members',
                    action: 'Add',
                    exclude: _members.map((m) => m.profile.id).toSet(),
                    onDone: (_, ids) => _run(
                      () => repo.addMembers(widget.chatId, ids),
                      'Members added',
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (final m in _members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: TRAvatar(
              name: m.profile.displayName,
              url: m.profile.avatarUrl,
              size: 38,
            ),
            title: Text(
              m.profile.id == me
                  ? '${m.profile.displayName} (you)'
                  : m.profile.displayName,
              style: TRText.body(14, c.text1),
            ),
            subtitle: Text(
              m.admin ? 'Admin' : '@${m.profile.username}',
              style: TRText.body(12, m.admin ? context.accent : c.text3),
            ),
            trailing: iAmAdmin && m.profile.id != me
                ? TRIconButton(
                    icon: Icons.remove_circle_outline,
                    tooltip: 'Remove from group',
                    onPressed: () => _run(
                      () => repo.removeMember(widget.chatId, m.profile.id),
                      'Removed',
                    ),
                  )
                : null,
          ),
        const SizedBox(height: 16),
        TRButton(
          label: 'Leave group',
          icon: Icons.logout_rounded,
          variant: TRButtonVariant.danger,
          onPressed: () async {
            try {
              await repo.leaveGroup(widget.chatId);
              if (!context.mounted) return;
              Navigator.pop(context);
              context.go('/app');
            } catch (_) {
              if (context.mounted)
                showToast(context, 'Could not leave the group', error: true);
            }
          },
        ),
      ],
    );
  }
}
