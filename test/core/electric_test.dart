import 'dart:math';

import 'package:easy_swapper/core/board/board_model.dart';
import 'package:easy_swapper/core/board/move_solver.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/board/tile_generator.dart';
import 'package:easy_swapper/core/levels/difficulty_ramp.dart';
import 'package:easy_swapper/core/levels/level_def.dart';
import 'package:easy_swapper/core/rules/scoring.dart';
import 'package:easy_swapper/core/session/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_helpers.dart';

Tile plantElectric(BoardModel board, Coord at) {
  final tile = Tile.electric(board.ids.nextId());
  board.setCoord(at, tile);
  return tile;
}

LevelDef zapLevel() => const LevelDef(
      id: 96,
      moves: -1,
      minRunLength: 3,
      operators: OperatorSet.tier2,
      objectives: [],
      starThresholds: [1, 2, 3],
    );

GameSession sessionOn(BoardModel board, {int seed = 1}) {
  final level = zapLevel();
  return GameSession(
    level: level,
    generator: TileGenerator(
      operators: level.operators,
      ids: board.ids,
      rng: Random(seed),
      bombChance: 0,
    ),
    board: board,
  );
}

void main() {
  group('targeting', () {
    test('takes every brick sharing the partner glyph, and nothing else', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      final sweep = electricSweep(
        board,
        partner: board.atCoord(const Coord(0, 0)), // a 7
        bothElectric: false,
      );

      expect(sweep.glyph, '7');
      for (final cell in sweep.cells) {
        expect(board.atCoord(cell)!.glyph, '7');
      }
      // Every 7 on the board, counted independently.
      var sevens = 0;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          if (board.at(x, y)!.glyph == '7') sevens++;
        }
      }
      expect(sweep.cells, hasLength(sevens));
    });

    test('an encased brick is targeted by the glyph showing through it', () {
      final board = boardFrom(['717', '242', '767']);
      board.setCoord(
        const Coord(2, 0),
        board.atCoord(const Coord(2, 0))!.encased(Armor.stone),
      );

      final sweep = electricSweep(
        board,
        partner: board.atCoord(const Coord(0, 0)),
        bothElectric: false,
      );
      expect(
        sweep.cells,
        contains(const Coord(2, 0)),
        reason: 'the casing hides it from equations, not from lightning',
      );
    });

    test('a partner with no glyph falls back to the commonest, and is stable',
        () {
      final board = boardFrom([
        '11122',
        '11133',
        '44455',
        '66677',
        '88899',
      ]);
      final bomb = Tile.bomb(board.ids.nextId());

      final first = electricSweep(board, partner: bomb, bothElectric: false);
      final second = electricSweep(board, partner: bomb, bothElectric: false);

      expect(first.glyph, '1', reason: 'six 1s beats every other count');
      expect(first.cells, hasLength(6));
      expect(second.glyph, first.glyph, reason: 'must not vary run to run');
    });

    test('a tie breaks on the lowest glyph, so a seeded run replays', () {
      final board = boardFrom(['99', '33']);
      final bomb = Tile.bomb(board.ids.nextId());
      expect(
        electricSweep(board, partner: bomb, bothElectric: false).glyph,
        '3',
      );
    });

    test('two electrics together take every digit', () {
      final board = boardFrom(['1+2', '3=4', '567']);
      final sweep =
          electricSweep(board, partner: null, bothElectric: true);

      expect(sweep.glyph, isNull);
      expect(sweep.cells, hasLength(7), reason: 'nine cells less + and =');
      for (final cell in sweep.cells) {
        expect(board.atCoord(cell)!.kind, TileKind.digit);
      }
    });
  });

  group('an electric makes a swap legal', () {
    test('the solver offers electric swaps on a board that cannot match', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      expect(findAllLegalMoves(board), isEmpty, reason: 'fixture must be dead');

      plantElectric(board, const Coord(2, 2));

      final moves = findAllLegalMoves(board);
      expect(moves, hasLength(4), reason: 'four orthogonal neighbours');
      expect(moves.every((m) => m.discharges), isTrue);
      expect(hasAnyLegalMove(board), isTrue);
    });

    test('the solver leaves the board untouched while probing', () {
      final board = boardFrom(['123', '456', '789']);
      plantElectric(board, const Coord(1, 1));
      final before = board.debugString();
      findAllLegalMoves(board);
      expect(board.debugString(), before);
    });

    test('a board holding only obstacles plus an electric is not deadlocked',
        () {
      final board = boardFrom(['123', '456', '789']);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 3; x++) {
          board.setCoord(
            Coord(x, y),
            board.at(x, y)!.encased(Armor.stone),
          );
        }
      }
      expect(hasAnyLegalMove(board), isFalse);

      plantElectric(board, const Coord(1, 1));
      expect(
        hasAnyLegalMove(board),
        isTrue,
        reason: 'an electric can always discharge, so this board has an out',
      );
    });
  });

  group('discharge', () {
    test('clears every matching brick plus the electric itself', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      plantElectric(board, const Coord(0, 1));
      final session = sessionOn(board);

      // Swapping the electric up onto a 7 sweeps every 7 on the board.
      final result = session.trySwap(const Coord(0, 1), const Coord(0, 0));
      expect(result.accepted, isTrue);

      final step = result.steps.first;
      expect(step.isZap, isTrue);
      expect(step.isDischarge, isTrue);
      expect(step.zaps, hasLength(1));
      expect(step.zaps.first.glyph, '7');
      // Nothing carrying a 7 is left, and the electric is spent.
      for (final tile in board.tiles) {
        expect(tile.isElectric, isFalse);
      }
      expect(step.score, greaterThan(0));
    });

    test('a discharge is not an equation, so it advances no solve counter', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      plantElectric(board, const Coord(0, 1));
      final session = sessionOn(board);

      final result = session.trySwap(const Coord(0, 1), const Coord(0, 0));
      final zap = result.steps.first;

      // The discharge step itself resolves no equation. Later links of the
      // cascade may well do - a refill can land one anywhere - and those are
      // real solves that should count, so the assertion is on the step rather
      // than on the session total.
      expect(zap.matches, isEmpty);
      expect(zap.zaps, hasLength(1));
      if (!result.boardReset) expect(session.electricsFired, 1);
    });

    test('encased targets take damage instead of clearing', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      board.setCoord(
        const Coord(4, 0),
        board.atCoord(const Coord(4, 0))!.encased(Armor.diamond),
      );
      plantElectric(board, const Coord(0, 1));
      final session = sessionOn(board);

      final result = session.trySwap(const Coord(0, 1), const Coord(0, 0));
      final step = result.steps.first;

      expect(step.cleared, isNot(contains(const Coord(4, 0))));
      expect(step.cracked[const Coord(4, 0)]?.armor, Armor.stone);
    });

    test('the board is left full and settled', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      plantElectric(board, const Coord(0, 1));
      final session = sessionOn(board);

      session.trySwap(const Coord(0, 1), const Coord(0, 0));

      expect(board.hasEmptyCells, isFalse);
      expect(board.tiles, hasLength(25));
      expect(board.tiles.map((t) => t.id).toSet(), hasLength(25));
      expect(board.findMatches(), isEmpty);
    });

    test('a bomb and an electric swapped together both fire', () {
      // The two resolve as one event rather than in sequence. In sequence the
      // bomb would have to be found again after the electric compacted and
      // refilled the board out from under its coordinate.
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      plantElectric(board, const Coord(2, 2));
      final bomb = Tile.bomb(board.ids.nextId());
      board.setCoord(const Coord(2, 1), bomb);
      final session = sessionOn(board);

      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));
      final step = result.steps.first;

      expect(step.isBlast, isTrue, reason: 'the bomb still goes off');
      expect(step.isZap, isTrue, reason: 'and so does the electric');
      expect(step.zaps.first.glyph, isNotNull,
          reason: 'a bomb partner has no glyph, so it falls back');
    });
  });

  group('a blast sets off what it sweeps', () {
    test('an electric caught in a blast fires instead of being deleted', () {
      // Bombs have always chained into bombs. An electric swept by a blast
      // used to be cleared in silence, which threw away the rarest brick on
      // the board for nothing.
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      board.setCoord(const Coord(2, 1), Tile.bomb(board.ids.nextId()));
      plantElectric(board, const Coord(4, 2));
      final session = sessionOn(board);

      // The bomb lands on row 2, whose sweep covers the electric at (4,2).
      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));
      final step = result.steps.first;

      expect(step.isBlast, isTrue);
      expect(step.isZap, isTrue, reason: 'the swept electric must fire');
      expect(step.zaps.single.origin, const Coord(4, 2));
      expect(
        step.zaps.single.glyph,
        isNotNull,
        reason: 'no partner, so it falls back to the commonest glyph',
      );
      if (!result.boardReset) expect(session.electricsFired, 1);
    });

    test('a chained electric takes its glyph off the whole board', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      board.setCoord(const Coord(2, 1), Tile.bomb(board.ids.nextId()));
      plantElectric(board, const Coord(4, 2));
      final session = sessionOn(board);

      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));
      final swept = result.steps.first.zaps.single.glyph!;
      for (final tile in board.tiles) {
        expect(
          tile.glyph == swept && !tile.isEncased,
          isFalse,
          reason: '$swept survived the discharge',
        );
      }
    });
  });

  group('power-ups are paid for what they destroyed', () {
    test('a casing that survived a blast is not billed as a kill', () {
      // It was, and twice over: once at the full per-cell blast rate and again
      // as a casing broken. A nine-cell cross over five stone bricks scored 75
      // for destroying four of them.
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      for (var x = 0; x < 5; x++) {
        board.setCoord(
          Coord(x, 2),
          board.at(x, 2)!.encased(Armor.stone),
        );
      }
      board.setCoord(const Coord(2, 1), Tile.bomb(board.ids.nextId()));
      final session = sessionOn(board);

      final step = session
          .trySwap(const Coord(2, 1), const Coord(2, 2))
          .steps
          .first;

      expect(step.cleared, hasLength(4), reason: 'only four bricks died');
      expect(step.cracked, hasLength(5));
      expect(
        step.score,
        scoreBlast(4).score + 5 * scoreCrack(Armor.none).score,
        reason: 'the blast is paid for four cells, not nine',
      );
    });

    test('a cell in both a cross and a sweep is charged once', () {
      final board = boardFrom([
        '71737',
        '24252',
        '76737',
        '31413',
        '57275',
      ]);
      plantElectric(board, const Coord(2, 2));
      board.setCoord(const Coord(2, 1), Tile.bomb(board.ids.nextId()));
      final session = sessionOn(board);

      final step = session
          .trySwap(const Coord(2, 1), const Coord(2, 2))
          .steps
          .first;

      // Whatever the split, the two power-ups between them can never be paid
      // for more cells than actually left the board.
      final blastRate = scoreBlast(step.cleared.length).score;
      final zapRate = scoreElectric(step.cleared.length).score;
      expect(step.score, lessThanOrEqualTo(blastRate + zapRate));
    });
  });

  group('scoreElectric', () {
    test('pays more per cell than a blast, which always clears a full cross',
        () {
      expect(scoreElectric(5).score, 20);
      expect(scoreElectric(5).score, greaterThan(scoreBlast(5).score));
    });

    test('escalates for a big sweep', () {
      expect(scoreElectric(10).score, 40 + (10 - 8) * 3);
      expect(scoreElectric(14).score, 56 + (14 - 8) * 3 + (14 - 12) * 6);
    });

    test('every tier has wording', () {
      expect(scoreElectric(3).feedback, isNotEmpty);
      expect(scoreElectric(6).feedback, contains('GOOD JOB'));
      expect(scoreElectric(10).feedback, contains('CHAIN LIGHTNING'));
      expect(scoreElectric(14).feedback, contains('THUNDERSTRUCK'));
    });
  });

  group('supply', () {
    test('generation never seeds an electric', () {
      for (final stage in DifficultyRamp.endless.stages) {
        for (var seed = 0; seed < 10; seed++) {
          final generator = TileGenerator(
            operators: OperatorSet.tier3,
            ids: TileIdGenerator(),
            rng: Random(seed),
            stage: stage,
          );
          final board = generator.generateBoard(width: 8, height: 8);
          expect(board.electricCells(), isEmpty,
              reason: 'stage ${stage.name} seed $seed');
        }
      }
    });

    test('a stage with no electric chance never draws one', () {
      final generator = TileGenerator(
        operators: OperatorSet.tier2,
        ids: TileIdGenerator(),
        rng: Random(2),
        stage: DifficultyStage.warmUp,
      );
      for (var i = 0; i < 400; i++) {
        expect(generator.nextRefillTile(allowElectric: true).isElectric,
            isFalse);
      }
    });

    test('the electric cap holds over a long run', () {
      const level = LevelDef(
        id: 0,
        moves: -1,
        minRunLength: 3,
        operators: OperatorSet.tier3,
        objectives: [],
        starThresholds: [1, 2, 3],
        ramp: DifficultyRamp.endless,
      );
      final generator = TileGenerator(
        operators: level.operators,
        ids: TileIdGenerator(),
        rng: Random(5),
      );
      final session = GameSession(level: level, generator: generator);

      for (var i = 0; i < 140; i++) {
        final move = session.hint();
        if (move == null) break;
        session.trySwap(move.a, move.b);
        expect(
          session.board.electricCells().length,
          lessThanOrEqualTo(GameSession.maxElectricsOnBoard),
          reason: 'over the electric cap on turn $i',
        );
      }
    });
  });
}
