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

/// Seals whatever is at [at] under [layers] of casing, keeping its glyph.
Tile encase(BoardModel board, Coord at, int layers) {
  final sealed = board.atCoord(at)!.encased(layers);
  board.setCoord(at, sealed);
  return sealed;
}

LevelDef armorLevel({DifficultyRamp ramp = DifficultyRamp.flat}) => LevelDef(
      id: 97,
      moves: -1,
      minRunLength: 3,
      operators: OperatorSet.tier2,
      objectives: const [],
      starThresholds: const [1, 2, 3],
      ramp: ramp,
    );

GameSession sessionOn(BoardModel board, {LevelDef? level, int seed = 1}) {
  final resolved = level ?? armorLevel();
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
  group('the tile model', () {
    test('an encased brick keeps its glyph but leaves the scan', () {
      const brick = Tile(id: 1, glyph: '7', kind: TileKind.digit);
      final stone = brick.encased(Armor.stone);

      expect(stone.glyph, '7', reason: 'the player can see what is trapped');
      expect(stone.scanGlyph, isNull, reason: 'but no equation can use it');
      expect(stone.isEncased, isTrue);
      expect(stone.canSwap, isFalse);
      expect(stone.isObstacle, isTrue);
    });

    test('a diamond takes two hits, a stone one', () {
      const brick = Tile(id: 1, glyph: '7', kind: TileKind.digit);
      final diamond = brick.encased(Armor.diamond);

      final once = diamond.cracked();
      expect(once.armor, Armor.stone);
      expect(once.isEncased, isTrue, reason: 'still sealed after one hit');

      final twice = once.cracked();
      expect(twice.armor, Armor.none);
      expect(twice.isEncased, isFalse);
      expect(twice.scanGlyph, '7', reason: 'playable the moment it is free');

      expect(twice.cracked().armor, Armor.none, reason: 'never goes negative');
    });

    test('cracking preserves the tile id', () {
      // The render layer finds a component by tile id, so an identity change
      // here would orphan the brick on screen.
      final diamond =
          const Tile(id: 42, glyph: '3', kind: TileKind.digit).encased(2);
      expect(diamond.cracked().id, 42);
    });

    test('an encased operator counts to the cap but not the floor', () {
      // The asymmetry the supply rules lean on: a sealed operator crowds the
      // board without being available to build anything through.
      final board = boardFrom(['1+2', '3=4', '567']);
      expect(board.operatorCount(), 2);
      expect(board.usableOperatorCount(), 2);
      expect(board.comparisonCount(), 1);

      encase(board, const Coord(1, 1), Armor.stone); // the '='

      expect(board.operatorCount(), 2, reason: 'still crowds the board');
      expect(board.usableOperatorCount(), 1, reason: 'no longer usable');
      expect(board.comparisonCount(), 0, reason: 'the floor must not count it');
    });

    test('a legacy isStone save loads as one layer of casing', () {
      final tile = Tile.fromJson({
        'id': 3,
        'glyph': '5',
        'kind': 'digit',
        'isStone': true,
      });
      expect(tile.armor, Armor.stone);
    });

    test('an encased brick round-trips through json', () {
      final original =
          const Tile(id: 9, glyph: '2', kind: TileKind.digit).encased(2);
      final restored = Tile.fromJson(original.toJson());
      expect(restored.armor, Armor.diamond);
      expect(restored.glyph, '2');
      expect(restored.id, 9);
    });
  });

  group('the solver refuses a pinned brick', () {
    test('a swap touching an encased brick is not a legal move', () {
      // The regression that matters most here. `trySwap` has always refused
      // these, but the solver did not - so a board where every remaining swap
      // touched a casing reported itself playable while the player had
      // nothing left to do, and a deadlock wipes the score.
      // Swapping the 3 and the 1 in column 2 turns row 0 into `1=1`.
      List<String> rows() => ['1=3', '451', '789'];
      bool touchesPin(Move m) =>
          m.a == const Coord(2, 1) || m.b == const Coord(2, 1);

      final loose = boardFrom(rows());
      expect(
        findAllLegalMoves(loose).where(touchesPin),
        isNotEmpty,
        reason: 'fixture must have a move through the cell being pinned',
      );

      final sealed = boardFrom(rows());
      encase(sealed, const Coord(2, 1), Armor.stone);
      expect(
        findAllLegalMoves(sealed).where(touchesPin),
        isEmpty,
        reason: 'the solver must not offer a swap the session will refuse',
      );
    });

    test('the session and the solver agree', () {
      final board = boardFrom(['1=3', '451', '789']);
      encase(board, const Coord(2, 1), Armor.stone);
      final session = sessionOn(board);

      final result =
          session.trySwap(const Coord(2, 0), const Coord(2, 1));
      expect(result.accepted, isFalse);
      expect(result.rejection, SwapRejection.lockedTile);
    });

    test('a board of nothing but casings is correctly deadlocked', () {
      final board = boardFrom(['1=1', '2=2', '3=3']);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 3; x++) {
          encase(board, Coord(x, y), Armor.stone);
        }
      }
      expect(hasAnyLegalMove(board), isFalse);
    });
  });

  group('impacts', () {
    test('an equation resolving beside a casing cracks it', () {
      // Swapping the 6 and the 5 in column 4 completes `2+3=5` across row 0.
      // The stone sits directly under the 3, so the run clearing is the
      // impact that breaks it - no bomb required.
      final board = boardFrom([
        '2+3=6',
        '11715',
        '88888',
        '11111',
        '22222',
      ]);
      encase(board, const Coord(2, 1), Armor.diamond);
      final session = sessionOn(board);

      final result = session.trySwap(const Coord(4, 0), const Coord(4, 1));
      expect(result.accepted, isTrue, reason: '2+3=5 should resolve');

      final step = result.steps.first;
      expect(step.cracked, hasLength(1));
      final cracked = step.cracked[const Coord(2, 1)]!;
      expect(cracked.glyph, '7');
      expect(cracked.armor, Armor.stone, reason: 'a diamond survives one hit');
    });

    test('a second impact frees the brick and pays the bonus', () {
      final board = boardFrom([
        '2+3=6',
        '11715',
        '88888',
        '11111',
        '22222',
      ]);
      encase(board, const Coord(2, 1), Armor.stone);
      final session = sessionOn(board);

      final result = session.trySwap(const Coord(4, 0), const Coord(4, 1));
      final freed = result.steps.first.cracked[const Coord(2, 1)]!;

      expect(freed.armor, Armor.none);
      expect(freed.scanGlyph, '7', reason: 'playable from the next scan on');
    });

    test('the session counters agree with the steps', () {
      // On a full board, where the run survives the turn and the counters are
      // not wiped. The five-by-five fixtures above deadlock the moment their
      // one comparison glyph clears, so guarding this assertion on
      // `boardReset` there meant it never ran at all.
      final level = armorLevel();
      final session = GameSession(
        level: level,
        generator: TileGenerator(
          operators: level.operators,
          ids: TileIdGenerator(),
          rng: Random(3),
        ),
      );
      final board = session.board;
      final move = session.hint();
      expect(move, isNotNull);

      // Work out what this move will clear, then seal a brick beside it, so
      // the impact is guaranteed rather than left to the seed.
      board.swap(move!.a, move.b);
      final doomed = board.cellsToClear(
        board.findMatchesAffectedBy(move.a, move.b, minRunLength: 3),
      );
      board.swap(move.a, move.b);
      expect(doomed, isNotEmpty);

      final victim = board
          .encasedNeighboursOf(doomed) // empty for now, so pick manually
          .firstOrNull ??
          [
            for (final cell in doomed)
              for (final n in [
                Coord(cell.x, cell.y + 1),
                Coord(cell.x, cell.y - 1),
              ])
                if (board.atCoord(n) != null && !doomed.contains(n)) n,
          ].first;
      board.setCoord(victim, board.atCoord(victim)!.encased(Armor.diamond));

      final result = session.trySwap(move.a, move.b);
      expect(result.accepted, isTrue);
      expect(result.boardReset, isFalse, reason: 'a wipe would zero the count');

      var cracks = 0;
      var freed = 0;
      for (final step in result.steps) {
        for (final tile in step.cracked.values) {
          cracks++;
          if (tile.armor == Armor.none) freed++;
        }
      }
      expect(cracks, greaterThan(0), reason: 'the sealed brick was not hit');
      expect(session.casingsCracked, cracks);
      expect(session.bricksFreed, freed);
    });

    test('damage leaves a brick that is not encased alone', () {
      final board = boardFrom(['123', '456', '789']);
      expect(board.damage([const Coord(0, 0)]), isEmpty);
      expect(board.at(0, 0)!.glyph, '1');
    });

    test('a freed brick keeps its id and becomes scannable', () {
      final board = boardFrom(['123', '456', '789']);
      final sealed = encase(board, const Coord(1, 1), Armor.stone);

      final cracked = board.damage([const Coord(1, 1)]);
      final freed = cracked[const Coord(1, 1)]!;

      expect(freed.id, sealed.id);
      expect(freed.isEncased, isFalse);
      expect(board.atCoord(const Coord(1, 1))!.scanGlyph, '5');
    });

    test('a casing blocks the equation it is sitting in', () {
      final board = boardFrom(['5=5', '123', '456']);
      expect(board.findMatches(), isNotEmpty);

      encase(board, const Coord(1, 0), Armor.stone);
      expect(
        board.findMatches(),
        isEmpty,
        reason: 'the sealed = cannot anchor a run',
      );
    });

    test('a half of a fused comparison is not dragged out of a casing', () {
      // `<` and `=` side by side render as one `<=`, so clearing one half has
      // always had to take the other - otherwise the player is left looking
      // at half an operator. An encased `=` never fused into the match in the
      // first place, so it must be left where it is.
      //
      // Column 1 reads `5<7`, which is true and is the only match here.
      List<String> rows() => ['951', '1<=', '476'];

      final loose = boardFrom(rows());
      final looseMatch = loose.findMatches();
      expect(looseMatch, hasLength(1), reason: 'fixture must match once');
      expect(
        loose.cellsToClear(looseMatch),
        contains(const Coord(2, 1)),
        reason: 'an ordinary = beside the < is part of the same glyph',
      );

      final sealed = boardFrom(rows());
      encase(sealed, const Coord(2, 1), Armor.stone);
      final sealedMatch = sealed.findMatches();
      expect(sealedMatch, hasLength(1), reason: 'the column still matches');
      expect(
        sealed.cellsToClear(sealedMatch),
        isNot(contains(const Coord(2, 1))),
        reason: 'a sealed = never fused, so it is not part of the run',
      );
    });
  });

  group('scoreCrack', () {
    test('freeing a brick pays far more than chipping one', () {
      expect(scoreCrack(Armor.stone).score, 2);
      expect(scoreCrack(Armor.none).score, 8);
      expect(scoreCrack(Armor.none).feedback, isNotEmpty);
      expect(scoreCrack(Armor.stone).feedback, isEmpty);
    });
  });

  group('supply', () {
    test('generation never seals a brick, at any stage', () {
      for (final stage in DifficultyRamp.endless.stages) {
        for (var seed = 0; seed < 12; seed++) {
          final generator = TileGenerator(
            operators: OperatorSet.tier3,
            ids: TileIdGenerator(),
            rng: Random(seed),
            stage: stage,
          );
          final board = generator.generateBoard(width: 8, height: 8);
          expect(
            board.encasedCells(),
            isEmpty,
            reason: 'stage ${stage.name} seed $seed dealt an opening obstacle',
          );
        }
      }
    });

    test('the flat ramp never produces a casing at all', () {
      final level = armorLevel();
      final generator = TileGenerator(
        operators: level.operators,
        ids: TileIdGenerator(),
        rng: Random(4),
      );
      final session = GameSession(level: level, generator: generator);

      for (var i = 0; i < 60; i++) {
        final move = session.hint();
        if (move == null) break;
        session.trySwap(move.a, move.b);
        expect(session.board.encasedCells(), isEmpty, reason: 'turn $i');
      }
    });

    test('the obstacle budget is never exceeded in a long run', () {
      // Every one of these is a cell no equation can run through, so the
      // shared ceiling is what actually protects the run from deadlocking.
      final level = LevelDef(
        id: 0,
        moves: -1,
        minRunLength: 3,
        operators: OperatorSet.tier3,
        objectives: const [],
        starThresholds: const [1, 2, 3],
        ramp: DifficultyRamp.endless,
      );
      final generator = TileGenerator(
        operators: level.operators,
        ids: TileIdGenerator(),
        rng: Random(6),
      );
      final session = GameSession(level: level, generator: generator);

      var sawCasing = false;
      for (var i = 0; i < 160; i++) {
        final move = session.hint();
        if (move == null) break;
        session.trySwap(move.a, move.b);

        if (session.board.encasedCells().isNotEmpty) sawCasing = true;
        expect(
          session.board.obstacleCells().length,
          lessThanOrEqualTo(session.stage.maxObstacles),
          reason: 'over the obstacle budget on turn $i '
              '(stage ${session.stage.name})',
        );
        expect(
          session.board.encasedCells().length,
          lessThanOrEqualTo(session.stage.maxEncased),
          reason: 'over the casing budget on turn $i',
        );
        expect(session.board.tiles, hasLength(64), reason: 'lost a tile at $i');
        expect(session.board.hasEmptyCells, isFalse, reason: 'hole at $i');
      }
      expect(sawCasing, isTrue, reason: 'this run should have dealt casings');
    });
  });
}
