import 'dart:math';

import 'package:easy_swapper/core/board/move_solver.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/board/tile_generator.dart';
import 'package:easy_swapper/core/levels/level_def.dart';
import 'package:flutter_test/flutter_test.dart';

TileGenerator generatorFor(OperatorSet operators, int seed) => TileGenerator(
      operators: operators,
      ids: TileIdGenerator(),
      rng: Random(seed),
    );

/// Mean, min and max of [values].
({double mean, int min, int max}) stats(List<int> values) {
  values.sort();
  return (
    mean: values.reduce((a, b) => a + b) / values.length,
    min: values.first,
    max: values.last,
  );
}

void main() {
  group('weighted draw', () {
    test('only ever emits glyphs from the level operator set', () {
      final gen = generatorFor(OperatorSet.tier1, 1);
      for (var i = 0; i < 2000; i++) {
        final tile = gen.next();
        expect(
          tile.kind == TileKind.digit ||
              OperatorSet.tier1.arithmetic.contains(tile.glyph) ||
              OperatorSet.tier1.comparison.contains(tile.glyph),
          isTrue,
          reason: 'tier 1 must not emit ${tile.glyph}',
        );
      }
    });

    test('exponent appears only in the tier that unlocks it', () {
      final tier1 = generatorFor(OperatorSet.tier1, 2);
      final glyphs = {for (var i = 0; i < 3000; i++) tier1.next().glyph};
      expect(glyphs, isNot(contains('^')));
      expect(glyphs, isNot(contains('*')));

      final tier4 = generatorFor(OperatorSet.tier4, 2);
      final tier4Glyphs = {for (var i = 0; i < 3000; i++) tier4.next().glyph};
      expect(tier4Glyphs, contains('^'));
    });

    test('the unconstrained draw already sits at the operator budget', () {
      // The board-level cap is the guarantee; this only checks the draw is not
      // fighting it, which would make the repair pass do all the work.
      final gen = generatorFor(OperatorSet.tier3, 3);
      final counts = <TileKind, int>{};
      const n = 20000;
      for (var i = 0; i < n; i++) {
        counts.update(gen.next().kind, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(counts[TileKind.digit]! / n, closeTo(0.670, 0.02));
      expect(counts[TileKind.arithmetic]! / n, closeTo(0.115, 0.02));
      expect(counts[TileKind.comparison]! / n, closeTo(0.215, 0.02));

      final operators =
          (counts[TileKind.arithmetic]! + counts[TileKind.comparison]!) / n;
      expect(operators, lessThanOrEqualTo(1 / 3));
    });

    test('low digits are drawn about twice as often as high ones', () {
      final gen = generatorFor(OperatorSet.tier1, 4);
      final counts = <String, int>{};
      for (var i = 0; i < 40000; i++) {
        final tile = gen.next();
        if (tile.kind == TileKind.digit) {
          counts.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      expect(counts['3']! / counts['8']!, closeTo(2.0, 0.25));
    });

    test('tile ids are unique', () {
      final gen = generatorFor(OperatorSet.tier2, 5);
      final ids = {for (var i = 0; i < 5000; i++) gen.next().id};
      expect(ids, hasLength(5000));
    });
  });

  group('generateBoard - the guarantee the game rests on', () {
    test('never returns a board that is already solved for the player', () {
      for (var seed = 0; seed < 120; seed++) {
        final gen = generatorFor(OperatorSet.tier1, seed);
        final board = gen.generateBoard(width: 8, height: 8);
        expect(board.findMatches(), isEmpty,
            reason: 'seed $seed handed out free score:\n${board.debugString()}');
      }
    });

    test('never returns a deadlocked board', () {
      for (var seed = 0; seed < 120; seed++) {
        final gen = generatorFor(OperatorSet.tier1, seed);
        final board = gen.generateBoard(width: 8, height: 8);
        expect(hasAnyLegalMove(board), isTrue,
            reason: 'seed $seed was born dead:\n${board.debugString()}');
      }
    });

    test('fills every cell', () {
      final gen = generatorFor(OperatorSet.tier2, 7);
      final board = gen.generateBoard(width: 8, height: 8);
      expect(board.hasEmptyCells, isFalse);
      expect(board.tiles, hasLength(64));
    });

    test('holds the guarantee on the harder tiers too', () {
      for (final operators in [
        OperatorSet.tier2,
        OperatorSet.tier3,
        OperatorSet.tier4,
      ]) {
        for (var seed = 0; seed < 40; seed++) {
          final gen = generatorFor(operators, seed);
          final board = gen.generateBoard(width: 8, height: 8);
          expect(board.findMatches(), isEmpty);
          expect(hasAnyLegalMove(board), isTrue);
        }
      }
    });

    test('holds the guarantee when long runs are required', () {
      // minRunLength 5 is where matches get genuinely scarce and the planted
      // fallback starts carrying the load.
      for (var seed = 0; seed < 40; seed++) {
        final gen = generatorFor(OperatorSet.tier2, seed);
        final board = gen.generateBoard(
          width: 8,
          height: 8,
          minRunLength: 5,
          minMoves: 1,
        );
        expect(board.findMatches(minRunLength: 5), isEmpty,
            reason: 'seed $seed:\n${board.debugString()}');
        expect(hasAnyLegalMove(board, minRunLength: 5), isTrue,
            reason: 'seed $seed:\n${board.debugString()}');
      }
    });

    test('a seeded generator is reproducible', () {
      final a = generatorFor(OperatorSet.tier1, 42).generateBoard(width: 8, height: 8);
      final b = generatorFor(OperatorSet.tier1, 42).generateBoard(width: 8, height: 8);
      expect(a.debugString(), b.debugString());
    });
  });

  group('difficulty measurement', () {
    // Not a pass/fail property so much as the instrument the weights are tuned
    // against. The band is wide on purpose; the printed numbers are the point.
    test('opening boards offer a playable number of moves', () {
      final counts = <int>[];
      for (var seed = 0; seed < 120; seed++) {
        final gen = generatorFor(OperatorSet.tier1, seed);
        final board = gen.generateBoard(width: 8, height: 8);
        counts.add(findAllLegalMoves(board).length);
      }
      final s = stats(counts);
      printOnFailure('tier1 opening moves: $s');
      // ignore: avoid_print
      print('tier1 8x8 opening legal moves - '
          'mean ${s.mean.toStringAsFixed(1)}, min ${s.min}, max ${s.max}');

      // The band tool/tune_weights.dart was swept against. Tier 1 is the
      // tightest tier because equality needs an exact sum.
      expect(s.min, greaterThan(0), reason: 'a dead opening board is a bug');
      expect(s.mean, greaterThan(7), reason: 'boards this tight are not fun');
      expect(s.mean, lessThan(25), reason: 'boards this loose are not a puzzle');
    });

    test('raising minRunLength measurably tightens the board', () {
      final loose = <int>[];
      final tight = <int>[];
      for (var seed = 0; seed < 40; seed++) {
        final board = generatorFor(OperatorSet.tier2, seed)
            .generateBoard(width: 8, height: 8);
        loose.add(findAllLegalMoves(board, minRunLength: 3).length);
        tight.add(findAllLegalMoves(board, minRunLength: 5).length);
      }
      final l = stats(loose);
      final t = stats(tight);
      // ignore: avoid_print
      print('tier2 moves - minRun 3: mean ${l.mean.toStringAsFixed(1)}, '
          'minRun 5: mean ${t.mean.toStringAsFixed(1)}');
      expect(t.mean, lessThan(l.mean));
    });
  });

  group('composition rules', () {
    test('operators never exceed a third of the board', () {
      for (final operators in [
        OperatorSet.tier1,
        OperatorSet.tier2,
        OperatorSet.tier3,
        OperatorSet.tier4,
      ]) {
        for (var seed = 0; seed < 30; seed++) {
          final gen = generatorFor(operators, seed);
          final board = gen.generateBoard(width: 8, height: 8);
          expect(
            board.operatorCount(),
            lessThanOrEqualTo(gen.operatorCapFor(8, 8)),
            reason: 'seed $seed:\n${board.debugString()}',
          );
        }
      }
    });

    test('the cap is a third of the cells', () {
      final gen = generatorFor(OperatorSet.tier1, 0);
      expect(gen.operatorCapFor(8, 8), 21);
      expect(gen.operatorCapFor(5, 5), 8);
    });

    test('no two operators are generated side by side', () {
      for (final operators in [
        OperatorSet.tier1,
        OperatorSet.tier2,
        OperatorSet.tier3,
        OperatorSet.tier4,
      ]) {
        for (var seed = 0; seed < 30; seed++) {
          final gen = generatorFor(operators, seed);
          final board = gen.generateBoard(width: 8, height: 8);
          expect(
            board.adjacentOperators(),
            isEmpty,
            reason: 'seed $seed:\n${board.debugString()}',
          );
        }
      }
    });

    test('the rules still hold when long runs are required', () {
      for (var seed = 0; seed < 25; seed++) {
        final gen = generatorFor(OperatorSet.tier2, seed);
        final board = gen.generateBoard(
          width: 8,
          height: 8,
          minRunLength: 5,
          minMoves: 1,
        );
        expect(board.adjacentOperators(), isEmpty, reason: 'seed $seed');
        expect(
          board.operatorCount(),
          lessThanOrEqualTo(gen.operatorCapFor(8, 8)),
          reason: 'seed $seed',
        );
      }
    });

    test('nextDigit never returns an operator', () {
      final gen = generatorFor(OperatorSet.tier4, 5);
      for (var i = 0; i < 500; i++) {
        final tile = gen.nextDigit();
        expect(tile.kind, TileKind.digit);
        expect(isOperator(tile), isFalse);
      }
    });

    test('a refill slot that forbids operators yields a digit', () {
      final gen = generatorFor(OperatorSet.tier2, 6);
      for (var i = 0; i < 200; i++) {
        final tile = gen.nextRefillTile(allowBomb: false, allowOperator: false);
        expect(isOperator(tile), isFalse);
      }
    });

    test('tier 4 no longer emits a bare bang', () {
      // `!` only means anything glued to an `=`, and operators can no longer be
      // generated adjacent, so it would be a permanently dead cell.
      final gen = generatorFor(OperatorSet.tier4, 7);
      final glyphs = {for (var i = 0; i < 4000; i++) gen.next().glyph};
      expect(glyphs, isNot(contains('!')));
    });
  });
}
