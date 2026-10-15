import 'package:flutter/widgets.dart';

import '../data/chat_repository.dart';
import '../data/contacts_repository.dart';
import 'auth/auth_service.dart';
import '../features/calls/call_controller.dart';
import 'theme/app_theme.dart';

/// Simple dependency container available everywhere via `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  final AuthService auth;
  final ThemeController theme;
  final ChatRepository chats;
  final ContactsRepository contacts;
  final CallController calls;

  const AppScope({
    super.key,
    required this.auth,
    required this.theme,
    required this.calls,
    required this.chats,
    required this.contacts,
    required super.child,
  });

  static AppScope of(BuildContext c) {
    final scope = c.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope == null) throw StateError('AppScope missing');
    return scope;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      old.chats != chats || old.auth != auth;
}
