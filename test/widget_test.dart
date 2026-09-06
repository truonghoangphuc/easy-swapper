import 'package:easy_swapper/game/swapper_game.dart';
import 'package:easy_swapper/main.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app boots into a game screen', (tester) async {
    await tester.pumpWidget(const EasySwapperApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byType(GameWidget<SwapperGame>), findsOneWidget);
  });
}
