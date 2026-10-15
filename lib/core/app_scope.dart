import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  AppScope({super.key, required this.auth, required this.theme, required this.calls, required super.child})
      : chats = ChatRepository(Supabase.instance.client),
        contacts = ContactsRepository(Supabase.instance.client);

  static AppScope of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}
