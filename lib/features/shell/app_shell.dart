import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_scope.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import 'nav_items.dart';

/// Desktop: left icon rail + content. Mobile: content + floating pill bottom bar.
class AppShell extends StatelessWidget {
  final Widget child;
  final String location;
  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppScope.of(context).auth.isAdmin;
    final items = navItems.where((i) => !i.adminOnly || isAdmin).toList();
    // Ctrl/Cmd + 1..5 jumps between sections on desktop.
    final shortcuts = <ShortcutActivator, VoidCallback>{};
    final desktopItems = items.where((i) => !i.mobileOnly).toList();
    for (var i = 0; i < desktopItems.length && i < 9; i++) {
      final key = LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i);
      shortcuts[SingleActivator(key, control: true)] = () => context.go(desktopItems[i].path);
      shortcuts[SingleActivator(key, meta: true)] = () => context.go(desktopItems[i].path);
    }

    return Scaffold(
      body: CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: true,
          child: MatrixBackground(
            child: AdaptiveBuilder(
              mobile: (_) => _MobileLayout(items: items, location: location, child: child),
              desktop: (_) => Row(children: [
                _DesktopRail(items: desktopItems, location: location),
                Expanded(child: child),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  final List<NavItem> items;
  final String location;
  const _DesktopRail({required this.items, required this.location});

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final profile = AppScope.of(context).auth.profile;
    return Container(
      width: 76,
      decoration: BoxDecoration(color: c.surface1.withValues(alpha: .6), border: Border(right: BorderSide(color: c.border))),
      child: SafeArea(
        right: false,
        child: Column(children: [
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TRRadius.lg),
              gradient: LinearGradient(colors: [context.accent, TRAccent.violet]),
            ),
            child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 24),
          for (final (i, item) in items.indexed) ...[
            _RailButton(item: item, active: isActive(item, location), shortcut: i + 1),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          Hoverable(
            tooltip: 'Profile & settings',
            onTap: () => context.go('/app/profile'),
            builder: (_, h) => AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: h || location.startsWith('/app/profile') ? context.accent : Colors.transparent, width: 2),
              ),
              child: TRAvatar(name: profile?.displayName ?? '?', url: profile?.avatarUrl, size: 38),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final NavItem item;
  final bool active;
  final int shortcut;
  const _RailButton({required this.item, required this.active, required this.shortcut});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Hoverable(
      tooltip: '${item.label}  (Ctrl+$shortcut)',
      onTap: () => context.go(item.path),
      builder: (_, h) => Stack(alignment: Alignment.centerLeft, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 3,
          height: active ? 24 : 0,
          decoration: BoxDecoration(color: context.accent, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TRRadius.xl),
              color: active ? context.accent.withValues(alpha: .14) : (h ? c.text1.withValues(alpha: .06) : Colors.transparent),
            ),
            child: Icon(active ? item.activeIcon : item.icon, size: 22, color: active ? context.accent : (h ? c.text1 : c.text2)),
          ),
        ),
      ]),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final List<NavItem> items;
  final String location;
  final Widget child;
  const _MobileLayout({required this.items, required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    // Hide the bar inside an open chat (full-screen conversation, like the site).
    final inChat = location.startsWith('/app/chat/');
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final mobileItems = items.where((i) => i.path != '/app/admin').toList();
    return Stack(children: [
      Positioned.fill(child: child),
      if (!inChat)
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + bottomInset,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: context.tr.bg,
              borderRadius: BorderRadius.circular(TRRadius.pill),
              border: Border.all(color: context.tr.border),
              boxShadow: TRShadow.md(Colors.black),
            ),
            child: Row(children: [
              for (final item in mobileItems) Expanded(child: _BarItem(item: item, active: isActive(item, location))),
            ]),
          ),
        ),
    ]);
  }
}

class _BarItem extends StatelessWidget {
  final NavItem item;
  final bool active;
  const _BarItem({required this.item, required this.active});
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        context.go(item.path);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TRRadius.pill),
          color: active ? c.text1.withValues(alpha: .05) : Colors.transparent,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(active ? item.activeIcon : item.icon, size: 20, color: active ? c.text1 : c.text2),
          const SizedBox(height: 4),
          Text(item.label,
              overflow: TextOverflow.ellipsis, style: TRText.body(9, active ? c.text1 : c.text2, w: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Space to keep content clear of the floating mobile bar.
double mobileBarClearance(BuildContext context) =>
    Responsive.isMobile(context) ? 96 + MediaQuery.paddingOf(context).bottom : 0;
