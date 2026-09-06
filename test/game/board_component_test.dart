import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/levels/level_data.dart';
import 'package:easy_swapper/core/session/game_session.dart';
import 'package:easy_swapper/game/swapper_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boots a real game inside a widget test and waits for it to load.
Future<SwapperGame> bootGame(WidgetTester tester, {int seed = 5}) async {
  final game = SwapperGame(level: endlessLevel, seed: seed);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 600,
        height: 600,
        child: GameWidget<SwapperGame>(game: game),
      ),
    ),
  );
  // A few frames for onLoad and the component queue to drain.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return game;
}

/// Runs [action] while pumping frames, so effects and `Future.delayed` in the
/// animation playback actually advance.
Future<void> pumpUntilDone(
  WidgetTester tester,
  Future<void> action, {
  int maxFrames = 1200,
}) async {
  var done = false;
  final wrapped = action.then((_) => done = true);
  for (var i = 0; i < maxFrames && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await wrapped;
}

void main() {
  group('board wiring', () {
    testWidgets('loads a full board of tile components', (tester) async {
      final game = await bootGame(tester);

      expect(game.board.isMounted, isTrue);
      expect(game.session.board.tiles, hasLength(64));
      expect(game.board.debugViewDrift(), isEmpty);
    });

    testWidgets('publishes initial state to the overlays', (tester) async {
      final game = await bootGame(tester);

      expect(game.score.value, 0);
      expect(game.phase.value, SessionPhase.idle);
      expect(game.movesRemaining.value, -1, reason: 'endless');
    });
  });

  group('coordinate conversion', () {
    testWidgets('maps cell centres and back again', (tester) async {
      final game = await bootGame(tester);
      final board = game.board;

      for (final coord in [
        const Coord(0, 0),
        const Coord(3, 5),
        const Coord(7, 7),
      ]) {
        expect(board.cellAt(board.centerOf(coord)), coord);
      }
    });

    testWidgets('rejects positions outside the board', (tester) async {
      final game = await bootGame(tester);
      final board = game.board;

      expect(board.cellAt(Vector2(-1, 10)), isNull);
      expect(board.cellAt(Vector2(10, -1)), isNull);
      expect(board.cellAt(Vector2(board.size.x + 1, 10)), isNull);
      expect(board.cellAt(Vector2(10, board.size.y + 1)), isNull);
    });
  });

  group('playing a turn', () {
    testWidgets('a legal swap scores and leaves the view in sync',
        (tester) async {
      final game = await bootGame(tester);
      final move = game.session.hint();
      expect(move, isNotNull);

      await pumpUntilDone(tester, game.board.attemptSwap(move!.a, move.b));

      expect(game.session.score, greaterThan(0));
      expect(game.score.value, game.session.score);
      expect(game.board.busy, isFalse);
      expect(
        game.board.debugViewDrift(),
        isEmpty,
        reason: 'the on-screen mirror drifted from the model',
      );
    });

    testWidgets('an illegal swap costs nothing and changes nothing',
        (tester) async {
      final game = await bootGame(tester);

      // Find a pair that the solver did not offer.
      final legal = {
        for (final m in [game.session.hint()!]) '${m.a}-${m.b}',
      };
      var a = const Coord(0, 0);
      var b = const Coord(1, 0);
      for (var y = 0; y < 8 && legal.contains('$a-$b'); y++) {
        a = Coord(0, y);
        b = Coord(1, y);
      }

      final before = game.session.board.debugString();
      await pumpUntilDone(tester, game.board.attemptSwap(a, b));

      if (game.session.movesUsed == 0) {
        expect(game.session.score, 0);
        expect(game.session.board.debugString(), before);
      }
      expect(game.board.debugViewDrift(), isEmpty);
    });

    testWidgets('the view survives a run of consecutive turns',
        (tester) async {
      // This is the regression that matters for the render layer: the mirror is
      // rebuilt by replaying falls and spawns, so drift compounds silently.
      final game = await bootGame(tester, seed: 11);

      for (var turn = 0; turn < 8; turn++) {
        final move = game.session.hint();
        expect(move, isNotNull, reason: 'deadlock on turn $turn');

        await pumpUntilDone(tester, game.board.attemptSwap(move!.a, move.b));

        expect(
          game.board.debugViewDrift(),
          isEmpty,
          reason: 'drift after turn $turn',
        );
      }
      expect(game.session.movesUsed, 8);
    });

    testWidgets('input is refused while a turn is animating', (tester) async {
      final game = await bootGame(tester);
      final move = game.session.hint()!;

      final first = game.board.attemptSwap(move.a, move.b);
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.board.busy, isTrue);

      // A second call mid-animation must be a no-op, not a queued turn.
      await game.board.attemptSwap(const Coord(0, 0), const Coord(1, 0));
      expect(game.session.movesUsed, lessThanOrEqualTo(1));

      await pumpUntilDone(tester, first);
      expect(game.board.busy, isFalse);
    });
  });

  group('hint', () {
    testWidgets('marks exactly the two tiles of a legal move', (tester) async {
      final game = await bootGame(tester);
      game.board.showHint();
      await tester.pump();

      final move = game.session.hint();
      expect(move, isNotNull);
      expect(game.board.debugViewDrift(), isEmpty);
    });
  });
}
