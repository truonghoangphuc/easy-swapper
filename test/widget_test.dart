import 'package:easy_swapper/main.dart';
import 'package:easy_swapper/services/progress_service.dart';
import 'package:easy_swapper/ui/level_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProgressService.init();
  });

  testWidgets('the app boots into the level select screen', (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LevelSelectScreen), findsOneWidget);
    expect(find.text('EASY SWAPPER'), findsOneWidget);
    expect(find.text('ENDLESS'), findsOneWidget);
    expect(find.text('CHALLENGE'), findsOneWidget);
  });

  testWidgets('tapping ENDLESS navigates to a game screen', (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    await tester.tap(find.text('ENDLESS'));
    // Pump enough frames for the route transition, but stop before the game
    // loop starts animating (which would cause pumpAndSettle to time out).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('the help screen opens and closes from the HUD', (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    // Navigate into a game first
    await tester.tap(find.text('ENDLESS'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

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

    // Navigate into a game first
    await tester.tap(find.text('ENDLESS'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byTooltip('Mute'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute'));
    // Toggling writes the preference, so the notifier updates a microtask later.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byTooltip('Unmute'), findsOneWidget);
  });
}
