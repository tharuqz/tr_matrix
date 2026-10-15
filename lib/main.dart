import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/chat_repository.dart';
import 'data/contacts_repository.dart';
import 'data/encrypted_cache.dart';
import 'data/offline_store.dart';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_scope.dart';
import 'core/auth/auth_service.dart';
import 'core/config.dart';
import 'core/theme/app_theme.dart';
import 'data/models.dart';
import 'core/maintenance.dart';
import 'core/notifications.dart';
import 'features/admin/admin_page.dart';
import 'features/auth/auth_page.dart';
import 'features/calls/call_controller.dart';
import 'features/calls/call_overlay.dart';
import 'features/calls/calls_page.dart';
import 'features/chats/chats_page.dart';
import 'features/contacts/contacts_page.dart';
import 'features/hives/hives_page.dart';
import 'features/profile/profile_page.dart';
import 'features/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux))
    MediaKit.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  final auth = AuthService(Supabase.instance.client);
  final theme = ThemeController();
  await theme.load();
  final calls = CallController(Supabase.instance.client, auth);
  final store = await EncryptedCache.create();
  final uid = auth.user?.id;
  if (uid != null) await store.open(uid);
  runApp(TRMatrixApp(auth: auth, theme: theme, calls: calls, store: store));
}

class TRMatrixApp extends StatefulWidget {
  final AuthService auth;
  final ThemeController theme;
  final CallController calls;
  final OfflineStore store;
  const TRMatrixApp({
    super.key,
    required this.auth,
    required this.theme,
    required this.calls,
    required this.store,
  });
  @override
  State<TRMatrixApp> createState() => _TRMatrixAppState();
}

class _TRMatrixAppState extends State<TRMatrixApp> {
  late final NotificationService _notify = NotificationService(
    Supabase.instance.client,
    widget.auth,
    widget.theme,
    (chatId) => _router.go('/app/chat/$chatId'),
  );

  late ChatRepository _chats;
  late final ContactsRepository _contacts = ContactsRepository(
    Supabase.instance.client,
  );
  void _accountChanged() {
    final uid = widget.auth.user?.id ?? 'signed-out';
    if (uid == _chats.ownerId) return;
    final old = _chats.ownerId;
    _chats.dispose();
    if (old != 'signed-out') unawaited(widget.store.clear(old));
    setState(
      () =>
          _chats = ChatRepository(Supabase.instance.client, widget.store, uid),
    );
  }

  @override
  void initState() {
    super.initState();
    _chats = ChatRepository(
      Supabase.instance.client,
      widget.store,
      widget.auth.user?.id ?? 'signed-out',
    );
    widget.auth.addListener(_accountChanged);
    AuthService.beforeSignOut = () async {
      try {
        await _notify.unregister().timeout(const Duration(seconds: 5));
      } catch (_) {}
      final uid = widget.auth.user?.id;
      _chats.dispose();
      if (uid != null) await widget.store.clear(uid);
    };
    _notify.start();
  }

  late final GoRouter _router = GoRouter(
    initialLocation: '/app',
    refreshListenable: widget.auth,
    redirect: (_, state) {
      final signedIn = widget.auth.isSignedIn;
      final atAuth = state.matchedLocation == '/auth';
      if (!signedIn && !atAuth) return '/auth';
      if (signedIn && atAuth) return '/app';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/app'),
      GoRoute(path: '/auth', builder: (_, __) => const AuthPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) => AppShell(
          location: state.matchedLocation,
          navigationShell: shell,
          child: shell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: ChatsPage()),
                routes: [
                  GoRoute(
                    path: 'chat/:chatId',
                    pageBuilder: (_, s) => NoTransitionPage(
                      child: ChatsPage(
                        chatId: s.pathParameters['chatId'],
                        initial: s.extra is ChatItem
                            ? s.extra as ChatItem
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/friends',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: ContactsPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/calls',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: CallsPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/hives',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: HivesPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/profile',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: ProfilePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/app/admin',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: AdminPage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    widget.auth.removeListener(_accountChanged);
    _chats.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: widget.auth,
      theme: widget.theme,
      calls: widget.calls,
      chats: _chats,
      contacts: _contacts,
      key: ValueKey(_chats.ownerId),
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.theme, widget.auth]),
        builder: (_, __) => MaterialApp.router(
          title: 'TR MATRIX',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(widget.theme),
          routerConfig: _router,
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(widget.theme.textScale),
              disableAnimations:
                  widget.theme.reducedMotion ||
                  MediaQuery.of(ctx).disableAnimations,
            ),
            child: MaintenanceGate(
              child: CallOverlay(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}
