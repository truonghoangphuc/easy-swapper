import 'package:easy_swapper/game/swapper_game.dart';
import 'package:easy_swapper/main.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the app boots into a game screen', (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(GameWidget<SwapperGame>), findsOneWidget);
  });

  testWidgets('the help screen opens and closes from the HUD', (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    expect(find.text('HOW TO PLAY'), findsNothing);

    await tester.tap(find.byTooltip('How to play'));
    await tester.pump();
    expect(find.text('HOW TO PLAY'), findsOneWidget);
    expect(find.textContaining('Swap to make the maths work'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('HOW TO PLAY'), findsNothing);
  });

  testWidgets('the mute button reflects and flips the sound setting',
      (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    expect(find.byTooltip('Mute'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute'));
    // Toggling writes the preference, so the notifier updates a microtask later.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byTooltip('Unmute'), findsOneWidget);
  });
}
