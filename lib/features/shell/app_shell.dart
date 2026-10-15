import 'package:flutter/material.dart';
import '../../core/motion.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scope.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import 'nav_items.dart';
import '../../core/notifications.dart';

class _ShellNavigation extends InheritedWidget {
  final StatefulNavigationShell shell;
  const _ShellNavigation({required this.shell, required super.child});
  @override
  bool updateShouldNotify(_ShellNavigation old) => old.shell != shell;
}

void _navigate(BuildContext context, String path) {
  const paths = [
    '/app',
    '/app/friends',
    '/app/calls',
    '/app/hives',
    '/app/profile',
    '/app/admin',
  ];
  final shell =
      context.dependOnInheritedWidgetOfExactType<_ShellNavigation>()?.shell;
  final index = paths.indexOf(path);
  if (shell == null || index < 0) {
    context.go(path);
    return;
  }
  shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

/// Desktop: left icon rail + content. Mobile: content + floating pill bottom bar.
class AppShell extends StatelessWidget {
  final Widget child;
  final String location;
  final StatefulNavigationShell navigationShell;
  const AppShell({
    super.key,
    required this.child,
    required this.location,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppScope.of(context).auth.isAdmin;
    final items = navItems.where((i) => !i.adminOnly || isAdmin).toList();
    // Ctrl/Cmd + 1..5 jumps between sections on desktop.
    final shortcuts = <ShortcutActivator, VoidCallback>{};
    final desktopItems = items.where((i) => !i.mobileOnly).toList();
    for (var i = 0; i < desktopItems.length && i < 9; i++) {
      final key = LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i);
      shortcuts[SingleActivator(key, control: true)] =
          () => navigationShell.goBranch(
            [
              '/app',
              '/app/friends',
              '/app/calls',
              '/app/hives',
              '/app/profile',
              '/app/admin',
            ].indexOf(desktopItems[i].path),
          );
      shortcuts[SingleActivator(key, meta: true)] =
          () => navigationShell.goBranch(
            [
              '/app',
              '/app/friends',
              '/app/calls',
              '/app/hives',
              '/app/profile',
              '/app/admin',
            ].indexOf(desktopItems[i].path),
          );
    }

    NotificationService.instance?.activeChatId =
        navigationShell.currentIndex == 0 && location.startsWith('/app/chat/')
            ? location.split('/').last
            : null;
    final content = MatrixPageMotion(
      trigger: navigationShell.currentIndex,
      child: child,
    );
    return _ShellNavigation(
      shell: navigationShell,
      child: Scaffold(
        body: CallbackShortcuts(
          bindings: shortcuts,
          child: Focus(
            autofocus: true,
            child: MatrixBackground(
              child: AdaptiveBuilder(
                mobile:
                    (_) => _MobileLayout(
                      items: items,
                      location: location,
                      child: content,
                    ),
                desktop:
                    (_) => Row(
                      children: [
                        _DesktopRail(items: desktopItems, location: location),
                        Expanded(child: content),
                      ],
                    ),
              ),
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
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.accent.withValues(alpha: .12),
              ),
              child: Icon(Icons.hub_rounded, color: context.accent, size: 20),
            ),
            const SizedBox(height: 24),
            for (final (i, item) in items.indexed) ...[
              _RailButton(
                item: item,
                active: isActive(item, location),
                shortcut: i + 1,
              ),
              const SizedBox(height: 6),
            ],
            const Spacer(),
            Hoverable(
              tooltip: 'Profile & settings',
              onTap: () => _navigate(context, '/app/profile'),
              builder:
                  (_, h) => AnimatedContainer(
                    duration: matrixDuration(context, 150),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            h || location.startsWith('/app/profile')
                                ? context.accent
                                : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: TRAvatar(
                      name: profile?.displayName ?? '?',
                      url: profile?.avatarUrl,
                      size: 38,
                    ),
                  ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final NavItem item;
  final bool active;
  final int shortcut;
  const _RailButton({
    required this.item,
    required this.active,
    required this.shortcut,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    return Hoverable(
      tooltip: '${item.label}  (Ctrl+$shortcut)',
      onTap: () => _navigate(context, item.path),
      builder:
          (_, h) => Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedContainer(
                duration: matrixDuration(context, 180),
                width: 3,
                height: active ? 24 : 0,
                decoration: BoxDecoration(
                  color: context.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: AnimatedContainer(
                  duration: matrixDuration(context, 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(TRRadius.pill),
                    color:
                        active
                            ? context.accent.withValues(alpha: .14)
                            : (h
                                ? c.text1.withValues(alpha: .06)
                                : Colors.transparent),
                  ),
                  child: Icon(
                    active ? item.activeIcon : item.icon,
                    size: 22,
                    color: active ? context.accent : (h ? c.text1 : c.text2),
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final List<NavItem> items;
  final String location;
  final Widget child;
  const _MobileLayout({
    required this.items,
    required this.location,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final inChat = location.startsWith('/app/chat/');
    final mobileItems = items.where((i) => i.path != '/app/admin').toList();
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (!inChat && MediaQuery.viewInsetsOf(context).bottom == 0)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: GlassPanel(
              radius: TRRadius.pill,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (final item in mobileItems)
                      Expanded(
                        child: _BarItem(
                          item: item,
                          active: isActive(item, location),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
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
        _navigate(context, item.path);
      },
      child: AnimatedContainer(
        duration: matrixDuration(context, 180),
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TRRadius.pill),
          color:
              active
                  ? context.accent.withValues(alpha: .16)
                  : Colors.transparent,
          border: Border.all(
            color:
                active
                    ? context.accent.withValues(alpha: .35)
                    : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? item.activeIcon : item.icon,
              size: 20,
              color: active ? context.accent : c.text2,
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: TRText.body(
                  9,
                  active ? context.accent : c.text2,
                  w: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Space to keep content clear of the floating mobile bar.
double mobileBarClearance(BuildContext context) =>
    Responsive.isMobile(context)
        ? 96 + MediaQuery.paddingOf(context).bottom
        : 0;
