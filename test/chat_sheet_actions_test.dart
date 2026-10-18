import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trmatrix_app/core/app_scope.dart';
import 'package:trmatrix_app/core/auth/auth_service.dart';
import 'package:trmatrix_app/core/theme/app_theme.dart';
import 'package:trmatrix_app/data/chat_repository.dart';
import 'package:trmatrix_app/data/contacts_repository.dart';
import 'package:trmatrix_app/data/models.dart';
import 'package:trmatrix_app/features/calls/call_controller.dart';
import 'package:trmatrix_app/features/chats/chat_theme_sheet.dart';
import 'package:trmatrix_app/features/chats/message_actions.dart';
import 'package:trmatrix_app/features/chats/disappearing_menu.dart';

class _Auth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Chats implements ChatRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Contacts implements ContactsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Calls implements CallController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  String? savedDuration;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:8766',
      anonKey: 'widget-test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rpc/set_disappearing')) {
          savedDuration = request.body;
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"disappear_after_sec":0}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  for (final size in [
    const Size(360, 640),
    const Size(320, 400),
    const Size(1280, 720),
  ]) {
    testWidgets('Disappearing menu saves one-hour duration at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      savedDuration = null;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DisappearingMenu(chatId: 'chat', labeled: true)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disappearing messages'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1 hour'));
      await tester.tap(find.text('1 hour'));
      await tester.pumpAndSettle();
      expect(savedDuration, contains('3600'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Message menu dispatches copy at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MsgAction? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMessageActions(
                  context,
                  msg: Message(
                    id: 'message',
                    chatId: 'chat',
                    senderId: 'me',
                    content: 'Hello',
                    createdAt: DateTime(2026),
                  ),
                  mine: true,
                  myReaction: null,
                  onReact: (_) {},
                  onAction: (action) => selected = action,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy text'));
      await tester.tap(find.text('Copy text'));
      await tester.pumpAndSettle();
      expect(selected, MsgAction.copy);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Theme reset restores the original look at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        AppScope(
          auth: _Auth(),
          theme: ThemeController(),
          chats: _Chats(),
          contacts: _Contacts(),
          calls: _Calls(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => ChatThemeSheet.show(context, 'chat'),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Wallpaper'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      final preferences = await SharedPreferences.getInstance();
      // Reset removes the saved theme so the chat returns to its original look.
      expect(preferences.getKeys().where((k) => k.startsWith('tr.chat-theme.')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
