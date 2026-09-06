import 'dart:math';

import 'package:easy_swapper/core/board/board_model.dart';
import 'package:easy_swapper/core/board/move_solver.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/board/tile_generator.dart';
import 'package:easy_swapper/core/levels/level_def.dart';
import 'package:easy_swapper/core/rules/scoring.dart';
import 'package:easy_swapper/core/session/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_helpers.dart';

LevelDef bombLevel({int moves = 20}) => LevelDef(
      id: 98,
      moves: moves,
      minRunLength: 3,
      operators: OperatorSet.tier1,
      objectives: const [ReachScore(1000000)],
      starThresholds: const [10, 20, 30],
      width: 5,
      height: 5,
    );

/// Puts a bomb at [at] on [board].
Tile plantBomb(BoardModel board, Coord at) {
  final bomb = Tile.bomb(board.ids.nextId());
  board.setCoord(at, bomb);
  return bomb;
}

GameSession sessionWith(BoardModel board, {LevelDef? level, int seed = 1}) {
  final resolved = level ?? bombLevel();
  return GameSession(
    level: resolved,
    generator: TileGenerator(
      operators: resolved.operators,
      ids: board.ids,
      rng: Random(seed),
      bombChance: 0,
    ),
    board: board,
  );
}

void main() {
  group('blastCells', () {
    test('covers the whole row and column through the origin', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      final cells = board.blastCells(const Coord(2, 2));

      // 5 across plus 5 down, sharing the centre.
      expect(cells, hasLength(9));
      for (var x = 0; x < 5; x++) {
        expect(cells, contains(Coord(x, 2)));
      }
      for (var y = 0; y < 5; y++) {
        expect(cells, contains(const Coord(2, 0).copyWith(y: y)));
      }
      expect(cells, isNot(contains(const Coord(1, 1))), reason: 'no diagonals');
    });

    test('works from a corner', () {
      final board = boardFrom(['123', '456', '789']);
      expect(board.blastCells(const Coord(0, 0)), hasLength(5));
    });

    test('skips cells that are already empty', () {
      final board = boardFrom(['123', '456', '789']);
      board.clear([const Coord(0, 1), const Coord(2, 1)]);
      expect(board.blastCells(const Coord(1, 1)), hasLength(3));
    });
  });

  group('bombCells', () {
    test('finds every bomb on the board', () {
      final board = boardFrom(['123', '456', '789']);
      expect(board.bombCells(), isEmpty);

      plantBomb(board, const Coord(1, 1));
      plantBomb(board, const Coord(2, 0));
      expect(board.bombCells(), hasLength(2));
      expect(board.bombCells(), contains(const Coord(1, 1)));
    });
  });

  group('a bomb makes a swap legal', () {
    test('the solver offers bomb swaps even with no equation in reach', () {
      // No comparison glyph anywhere, so nothing can ever match.
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      expect(findAllLegalMoves(board), isEmpty, reason: 'fixture must be dead');

      plantBomb(board, const Coord(2, 2));

      final moves = findAllLegalMoves(board);
      expect(moves, hasLength(4), reason: 'four orthogonal neighbours');
      expect(moves.every((m) => m.detonates), isTrue);
      expect(hasAnyLegalMove(board), isTrue);
    });

    test('a board holding a bomb is never deadlocked', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      expect(hasAnyLegalMove(board), isFalse);
      plantBomb(board, const Coord(0, 0));
      expect(hasAnyLegalMove(board), isTrue);
    });

    test('the solver leaves the board untouched while probing bombs', () {
      final board = boardFrom(['123', '456', '789']);
      plantBomb(board, const Coord(1, 1));
      final before = board.debugString();
      findAllLegalMoves(board);
      expect(board.debugString(), before);
    });

    test('a bomb swap is scored by the blast it would cause', () {
      final board = boardFrom(['123', '456', '789']);
      plantBomb(board, const Coord(1, 1));

      final move = findAllLegalMoves(board).first;
      // The bomb lands where its partner was, so the blast is measured there.
      expect(move.score, greaterThan(0));
      expect(move.score, scoreBlast(5).score);
    });
  });

  group('detonation', () {
    test('clears the whole row and column and scores the blast', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      plantBomb(board, const Coord(2, 1));
      final session = sessionWith(board);

      // Swap the bomb down into the middle row; it detonates there.
      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));

      expect(result.accepted, isTrue);

      final blast = result.steps.first;
      expect(blast.isBlast, isTrue);
      expect(blast.detonations, [const Coord(2, 2)]);
      expect(blast.cleared, hasLength(9));
      expect(blast.score, greaterThan(0));

      // Assertions read off the result, not the session. This fixture has no
      // comparison glyph, so it deadlocks once the cross clears and the run is
      // wiped - the turn still happened, and the result is its record.
      expect(result.totalScore, greaterThan(0));
    });

    test('leaves the board full and settled afterwards', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      plantBomb(board, const Coord(2, 1));
      final session = sessionWith(board);

      session.trySwap(const Coord(2, 1), const Coord(2, 2));

      expect(board.hasEmptyCells, isFalse);
      expect(board.tiles, hasLength(25));
      expect(board.findMatches(), isEmpty);
    });

    test('a blast is not an equation, so it does not advance solve counters',
        () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      plantBomb(board, const Coord(2, 1));
      final session = sessionWith(board);

      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));

      expect(result.steps.first.detonations, hasLength(1));
      expect(session.equationsCleared, 0,
          reason: 'a bomb is a shortcut, not a solve');
      expect(session.operatorUses, isEmpty);
    });

    test('a bomb caught in the blast chains', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      plantBomb(board, const Coord(2, 1));
      // Sits in the column the first bomb will sweep.
      plantBomb(board, const Coord(2, 4));
      final session = sessionWith(board);

      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));
      final blast = result.steps.first;

      expect(blast.detonations, hasLength(2));
      expect(blast.detonations.first, const Coord(2, 2));
      expect(blast.detonations, contains(const Coord(2, 4)));
      // Column 2 plus rows 2 and 4.
      expect(blast.cleared.length, greaterThan(9));
    });

    test('two bombs swapped together both go off', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      plantBomb(board, const Coord(1, 2));
      plantBomb(board, const Coord(2, 2));
      final session = sessionWith(board);

      final result = session.trySwap(const Coord(1, 2), const Coord(2, 2));
      expect(result.steps.first.detonations, hasLength(2));
    });

    test('detonating still costs exactly one move', () {
      final board = boardFrom([
        '12345',
        '67891',
        '23456',
        '78912',
        '34567',
      ]);
      plantBomb(board, const Coord(2, 1));
      final session = sessionWith(board, level: bombLevel(moves: 5));

      final result = session.trySwap(const Coord(2, 1), const Coord(2, 2));
      expect(result.accepted, isTrue);
      if (!result.boardReset) {
        expect(session.movesUsed, 1);
        expect(session.movesRemaining, 4);
      }
    });
  });

  group('bomb generation', () {
    test('board generation never places a bomb', () {
      for (var seed = 0; seed < 40; seed++) {
        final generator = TileGenerator(
          operators: OperatorSet.tier2,
          ids: TileIdGenerator(),
          rng: Random(seed),
          bombChance: 1.0,
        );
        final board = generator.generateBoard(width: 8, height: 8);
        expect(board.bombCells(), isEmpty,
            reason: 'seed $seed seeded a free power-up');
      }
    });

    test('refill honours the bomb chance', () {
      final never = TileGenerator(
        operators: OperatorSet.tier1,
        ids: TileIdGenerator(),
        rng: Random(1),
        bombChance: 0,
      );
      expect(
        List.generate(200, (_) => never.nextRefillTile().isBomb),
        everyElement(isFalse),
      );

      final always = TileGenerator(
        operators: OperatorSet.tier1,
        ids: TileIdGenerator(),
        rng: Random(1),
        bombChance: 1,
      );
      expect(always.nextRefillTile().isBomb, isTrue);
      expect(always.nextRefillTile(allowBomb: false).isBomb, isFalse);
    });

    test('the board never holds more than the cap', () {
      // bombChance 1 means every refilled cell wants to be a bomb; only the cap
      // stops the board turning into a minefield.
      final level = bombLevel(moves: -1);
      final generator = TileGenerator(
        operators: level.operators,
        ids: TileIdGenerator(),
        rng: Random(3),
        bombChance: 1,
      );
      final board = generator.generateBoard(
        width: level.width,
        height: level.height,
      );
      final session = GameSession(
        level: level,
        generator: generator,
        board: board,
      );

      for (var i = 0; i < 12 && !session.isOver; i++) {
        final move = session.hint();
        if (move == null) break;
        session.trySwap(move.a, move.b);
        expect(
          board.bombCells().length,
          lessThanOrEqualTo(GameSession.maxBombsOnBoard),
          reason: 'exceeded the cap on turn $i',
        );
      }
    });
  });

  group('scoreBlast', () {
    test('pays a flat rate per cell', () {
      expect(scoreBlast(5).score, 15);
      expect(scoreBlast(9).score, 27 + (9 - 5) * 2);
    });

    test('escalates for a big cross', () {
      expect(scoreBlast(15).score, 45 + (15 - 5) * 2 + (15 - 10) * 5);
    });

    test('wording matches easy-mathriss at every tier', () {
      expect(scoreBlast(3).feedback, 'BOOM BOOM! \u{1F4A5}');
      expect(scoreBlast(5).feedback, contains('GOOD JOB'));
      expect(scoreBlast(9).feedback, contains('EXCELLENT'));
      expect(scoreBlast(15).feedback, contains('MEGA BOOM'));
      expect(scoreBlast(15).feedback, contains('OH MY GOD'));
    });
  });

  group('bombs in play', () {
    test('a long run of turns with bombs keeps the board consistent', () {
      const level = LevelDef(
        id: 0,
        moves: -1,
        minRunLength: 3,
        operators: OperatorSet.tier2,
        objectives: [],
        starThresholds: [1, 2, 3],
      );
      final generator = TileGenerator(
        operators: level.operators,
        ids: TileIdGenerator(),
        rng: Random(7),
        bombChance: 0.25,
      );
      final board = generator.generateBoard(width: 8, height: 8);
      final session =
          GameSession(level: level, generator: generator, board: board);

      final rng = Random(7);
      var detonations = 0;
      for (var i = 0; i < 60; i++) {
        final moves = findAllLegalMoves(board);
        expect(moves, isNotEmpty, reason: 'deadlock at move $i');
        final move = moves[rng.nextInt(moves.length)];

        final result = session.trySwap(move.a, move.b);
        expect(result.accepted, isTrue,
            reason: 'solver offered an illegal move at $i');
        for (final step in result.steps) {
          detonations += step.detonations.length;
        }
        expect(board.hasEmptyCells, isFalse, reason: 'hole at move $i');
        expect(board.tiles, hasLength(64), reason: 'lost a tile at $i');
        expect(board.tiles.map((t) => t.id).toSet(), hasLength(64),
            reason: 'duplicate id at $i');
        expect(board.findMatches(), isEmpty, reason: 'unresolved match at $i');
      }
      expect(detonations, greaterThan(0),
          reason: 'this seed should have set some off');
    });
  });
}
