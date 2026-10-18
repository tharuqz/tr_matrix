import 'package:flutter_test/flutter_test.dart';
import 'package:trmatrix_app/core/animated_emoji.dart';

void main() {
  test('maps emoji with variation selector, skin tone and flags', () {
    expect(animatedEmojiCode('❤️'), '2764');
    expect(animatedEmojiCode('👍🏽'), '1f44d');
    expect(animatedEmojiCode('🇯🇵'), '1f1ef-1f1f5');
    expect(animatedEmojiCode('a'), isNull);
  });

  test('mixed text is animated, not only emoji-only messages', () {
    expect(AnimatedEmojiText.hasAnimated('hello 😂 friend'), isTrue);
    expect(isEmojiOnlyText('hello 😂'), isFalse);
    expect(isEmojiOnlyText('😂🔥'), isTrue);
  });
}
