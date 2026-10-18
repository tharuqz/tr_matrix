import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trmatrix_app/data/chat_folders_store.dart';

void main() {
  late ChatFoldersStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = ChatFoldersStore();
  });

  test(
    'creates a custom folder with its chats and keeps it after reload',
    () async {
      final f = await store.create('Work', ['a', 'b']);
      expect(f, isNotNull);
      final again = ChatFoldersStore();
      await again.load();
      expect(again.folders.single.name, 'Work');
      expect(again.folders.single.chatIds, ['a', 'b']);
    },
  );

  test(
    'built-in folder names All, Hives and Archived cannot be reused',
    () async {
      expect(await store.create('Hives', []), isNull);
      expect(await store.create('all', []), isNull);
      expect(await store.create('Archived', []), isNull);
    },
  );

  test('duplicate and empty names are rejected', () async {
    await store.create('Family', []);
    expect(await store.create('family', []), isNull);
    expect(await store.create('   ', []), isNull);
  });

  test(
    'toggling a chat adds then removes it; deleting keeps other folders',
    () async {
      final a = (await store.create('A', []))!;
      await store.create('B', []);
      await store.toggleChat(a.id, 'x');
      expect(store.folders.first.chatIds, ['x']);
      await store.toggleChat(a.id, 'x');
      expect(store.folders.first.chatIds, isEmpty);
      await store.delete(a.id);
      expect(store.folders.map((f) => f.name), ['B']);
    },
  );
}
