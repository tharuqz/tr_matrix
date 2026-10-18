import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trmatrix_app/core/security/app_lock.dart';
import 'package:trmatrix_app/features/security/lock_screen.dart';
import 'package:trmatrix_app/widgets/app_layer_overlay.dart';

void main() {
  testWidgets(
    'PIN-only lock unlocks with keyboard after fingerprint is disabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final lock = AppLock.instance;
      await lock.setPin('2468', bio: true);
      expect(await lock.setBiometric(false), isTrue);
      lock.lockNow();
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          theme: ThemeData(platform: TargetPlatform.windows),
          builder: (_, child) => AppLayerOverlay(
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
          home: const Scaffold(body: Text('Chat')),
        ),
      );
      await tester.pump();
      final pad = find.byType(PinPad);
      final size = tester.getSize(pad);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(400));
      expect(lock.useBiometric, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4, character: '4');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6, character: '6');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8, character: '8');
      await tester.pump();
      expect(lock.locked, isFalse);
      expect(tester.takeException(), isNull);
      expect(navigation.currentState, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await lock.disable();
    },
  );

  testWidgets('PIN-only lock unlocks through keypad taps', (tester) async {
    final lock = AppLock.instance;
    await lock.setPin('2468', bio: false);
    lock.lockNow();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        builder: (_, child) => AppLayerOverlay(
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        ),
        home: const Scaffold(body: Text('Chat')),
      ),
    );
    await tester.pump();
    for (final digit in ['2', '4', '6', '8']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(lock.locked, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await lock.disable();
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('Keyboard PIN creation works on $platform', (tester) async {
      SharedPreferences.setMockInitialValues({});
      String? entered;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: PinPad(
            title: 'Create a PIN',
            subtitle: '4 to 8 digits',
            checkPin: false,
            onDone: () {},
            onEntered: (value) => entered = value,
          ),
        ),
      );
      await tester.pump();
      for (final key in [
        (LogicalKeyboardKey.digit2, '2'),
        (LogicalKeyboardKey.digit4, '4'),
        (LogicalKeyboardKey.digit6, '6'),
        (LogicalKeyboardKey.digit8, '8'),
      ]) {
        await tester.sendKeyEvent(key.$1, character: key.$2);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(entered, '2468');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'global controls have an overlay and router still handles navigation',
    (tester) async {
      final navigation = GlobalKey<NavigatorState>();
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          builder: (_, child) => AppLayerOverlay(
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Material(
                    child: IconButton(
                      tooltip: 'Zone control',
                      icon: const Icon(Icons.mic),
                      onPressed: () => taps++,
                    ),
                  ),
                ),
              ],
            ),
          ),
          home: const Scaffold(body: Text('Chat')),
        ),
      );
      await tester.longPress(find.byIcon(Icons.mic));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      expect(taps, 1);
      final nav = navigation.currentState;
      expect(nav, isNotNull);
      nav?.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Zone')),
        ),
      );
      await tester.pumpAndSettle();
      expect(nav?.canPop(), isTrue);
      nav?.pop();
      await tester.pumpAndSettle();
      expect(nav?.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
