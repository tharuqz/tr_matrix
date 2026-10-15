import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
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
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
    MediaKit.ensureInitialized();
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  final auth = AuthService(Supabase.instance.client);
  final theme = ThemeController();
  await theme.load();
  final calls = CallController(Supabase.instance.client, auth);
  runApp(TRMatrixApp(auth: auth, theme: theme, calls: calls));
}

class TRMatrixApp extends StatefulWidget {
  final AuthService auth;
  final ThemeController theme;
  final CallController calls;
  const TRMatrixApp({super.key, required this.auth, required this.theme, required this.calls});
  @override
  State<TRMatrixApp> createState() => _TRMatrixAppState();
}

class _TRMatrixAppState extends State<TRMatrixApp> {
  late final NotificationService _notify =
      NotificationService(Supabase.instance.client, widget.auth, widget.theme, (chatId) => _router.go('/app/chat/$chatId'));

  @override
  void initState() {
    super.initState();
    AuthService.beforeSignOut = _notify.unregister;
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
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/app', pageBuilder: (_, __) => const NoTransitionPage(child: ChatsPage())),
          GoRoute(
            path: '/app/chat/:chatId',
            pageBuilder: (_, s) => NoTransitionPage(
              child: ChatsPage(chatId: s.pathParameters['chatId'], initial: s.extra is ChatItem ? s.extra as ChatItem : null),
            ),
          ),
          GoRoute(path: '/app/friends', pageBuilder: (_, __) => const NoTransitionPage(child: ContactsPage())),
          GoRoute(
            path: '/app/calls',
            pageBuilder: (_, __) => const NoTransitionPage(child: CallsPage()),
          ),
          GoRoute(
            path: '/app/hives',
            pageBuilder: (_, __) => const NoTransitionPage(child: HivesPage()),
          ),
          GoRoute(path: '/app/profile', pageBuilder: (_, __) => const NoTransitionPage(child: ProfilePage())),
          GoRoute(
            path: '/app/admin',
            pageBuilder: (_, __) => const NoTransitionPage(child: AdminPage()),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AppScope(
      auth: widget.auth,
      theme: widget.theme,
      calls: widget.calls,
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
              disableAnimations: widget.theme.reducedMotion || MediaQuery.of(ctx).disableAnimations,
            ),
            child: MaintenanceGate(child: CallOverlay(child: child ?? const SizedBox.shrink())),
          ),
        ),
      ),
    );
  }
}
