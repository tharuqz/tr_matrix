import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trmatrix_app/core/theme/chat_appearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a change in the theme page reaches the open chat immediately',
      () async {
    final chat = ChatAppearanceStore('u1', 'c1');
    final sheet = ChatAppearanceStore('u1', 'c1');
    await Future<void>.delayed(Duration.zero);
    expect(chat.customized, isFalse);
    await sheet.patch({'color': '#ec4899'});
    expect(chat.value.color, '#ec4899');
    expect(chat.customized, isTrue);
    chat.dispose();
    sheet.dispose();
  });

  test('another chat is not affected', () async {
    final a = ChatAppearanceStore('u1', 'a');
    final b = ChatAppearanceStore('u1', 'b');
    await a.patch({'shape': 'capsule'});
    expect(b.value.shape, isNot('capsule'));
    a.dispose();
    b.dispose();
  });

  test('reset brings back the original look and survives reopening', () async {
    final s = ChatAppearanceStore('u1', 'c2');
    await s.patch({'dim': 40});
    await s.reset();
    expect(s.customized, isFalse);
    s.dispose();
    final again = ChatAppearanceStore('u1', 'c2');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(again.customized, isFalse);
    again.dispose();
  });
}
