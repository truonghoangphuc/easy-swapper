import 'dart:math';

import 'package:easy_swapper/core/board/move_solver.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/board/tile_generator.dart';
import 'package:easy_swapper/core/board/tile_queue.dart';
import 'package:easy_swapper/core/levels/level_def.dart';
import 'package:easy_swapper/core/session/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

GameSession session({int seed = 3, double bombChance = 0}) {
  const level = LevelDef(
    id: 0,
    moves: -1,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [],
    starThresholds: [1, 2, 3],
  );
  return GameSession(
    level: level,
    generator: TileGenerator(
      operators: level.operators,
      ids: TileIdGenerator(),
      rng: Random(seed),
      bombChance: bombChance,
    ),
  );
}

Tile digit(int id) => Tile(id: id, glyph: '1', kind: TileKind.digit);

void main() {
  group('TileQueue', () {
    test('starts empty, one slot per column', () {
      final queue = TileQueue(8);
      expect(queue.slots, hasLength(8));
      expect(queue.slots, everyElement(isNull));
      expect(queue.isFull, isFalse);
      expect(queue.emptyColumns(), [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('fill and peek address a single column', () {
      final queue = TileQueue(4);
      queue.fill(2, digit(7));

      expect(queue.peek(2)!.id, 7);
      expect(queue.peek(0), isNull);
      expect(queue.emptyColumns(), [0, 1, 3]);
      expect(queue.count, 1);
    });

    test('take empties the slot and hands back the tile', () {
      final queue = TileQueue(3);
      queue.fill(1, digit(5));

      expect(queue.take(1)!.id, 5);
      expect(queue.peek(1), isNull);
      expect(queue.take(1), isNull, reason: 'the slot is empty now');
    });

    test('counts operators, comparisons and bombs it holds', () {
      final queue = TileQueue(4);
      queue.fill(0, digit(1));
      queue.fill(1, const Tile(id: 2, glyph: '+', kind: TileKind.arithmetic));
      queue.fill(2, const Tile(id: 3, glyph: '=', kind: TileKind.comparison));
      queue.fill(3, Tile.bomb(4));

      expect(queue.operatorCount(), 2);
      expect(queue.comparisonCount(), 1);
      expect(queue.bombCount(), 1);
    });

    test('clear empties every slot', () {
      final queue = TileQueue(3);
      queue.fill(0, digit(1));
      queue.clear();
      expect(queue.slots, everyElement(isNull));
    });
  });

  group('the preview tells the truth', () {
    test('a session starts with every column previewed', () {
      final s = session();
      expect(s.queue.isFull, isTrue);
      expect(s.queue.width, s.board.width);
    });

    test('each column receives exactly the tile shown above it', () {
      final s = session();
      final rng = Random(11);

      for (var turn = 0; turn < 40; turn++) {
        final moves = findAllLegalMoves(s.board);
        if (moves.isEmpty) break;

        final promised = [
          for (var x = 0; x < s.board.width; x++) s.queue.peek(x)?.id,
        ];
        final move = moves[rng.nextInt(moves.length)];
        final result = s.trySwap(move.a, move.b);
        if (result.boardReset) continue;

        // Only the first refill of the turn. A cascade refills once per link and
        // tops the preview up between them, so later links legitimately deliver
        // tiles the player saw appear mid-turn, not before it.
        final firstByColumn = <int, int>{};
        for (final spawn in result.steps.first.spawns) {
          firstByColumn.putIfAbsent(spawn.to.x, () => spawn.tile.id);
        }

        firstByColumn.forEach((column, id) {
          expect(
            id,
            promised[column],
            reason: 'column $column was shown ${promised[column]} but got $id '
                'on turn $turn',
          );
        });
      }
    });

    test('the tile shown lands deepest, with the rest stacked on it', () {
      // The previewed brick is the next to drop, so it leads and comes to rest
      // at the bottom of the gap.
      final s = session();
      final moves = findAllLegalMoves(s.board);
      final promised = [
        for (var x = 0; x < s.board.width; x++) s.queue.peek(x)?.id,
      ];
      final result = s.trySwap(moves.first.a, moves.first.b);

      final byColumn = <int, List<({int y, int id})>>{};
      for (final spawn in result.steps.first.spawns) {
        byColumn
            .putIfAbsent(spawn.to.x, () => [])
            .add((y: spawn.to.y, id: spawn.tile.id));
      }

      byColumn.forEach((column, arrivals) {
        arrivals.sort((a, b) => b.y.compareTo(a.y));
        expect(arrivals.first.id, promised[column],
            reason: 'column $column: the previewed brick must land deepest');
      });
    });

    test('every column is topped back up after a turn', () {
      final s = session();
      final rng = Random(12);

      for (var turn = 0; turn < 30; turn++) {
        final moves = findAllLegalMoves(s.board);
        if (moves.isEmpty) break;
        s.trySwap(moves[rng.nextInt(moves.length)].a,
            moves[rng.nextInt(moves.length)].b);

        expect(s.queue.isFull, isTrue, reason: 'gap in the preview at $turn');
      }
    });

    test('a deadlock reset deals a new preview too', () {
      final s = session();
      final before = [for (final t in s.queue.slots) t!.id];

      s.resetAfterDeadlock();

      expect(s.queue.isFull, isTrue);
      expect(
        [for (final t in s.queue.slots) t!.id],
        isNot(before),
        reason: 'a stale preview would promise tiles from the old board',
      );
    });
  });

  group('queued tiles respect the board budgets', () {
    test('board plus queue never exceeds the operator cap', () {
      final s = session(seed: 5);
      final cap = s.generator.operatorCapFor(8, 8);
      final rng = Random(14);

      for (var turn = 0; turn < 60; turn++) {
        final moves = findAllLegalMoves(s.board);
        if (moves.isEmpty) break;
        s.trySwap(moves[rng.nextInt(moves.length)].a,
            moves[rng.nextInt(moves.length)].b);

        expect(s.board.operatorCount(), lessThanOrEqualTo(cap),
            reason: 'over the cap after turn $turn');
      }
    });

    test('the queue restocks comparisons when the board runs low', () {
      final s = session(seed: 6);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          if (s.board.at(x, y)?.kind == TileKind.comparison) {
            s.board.set(x, y, s.generator.nextDigit());
          }
        }
      }
      s.queue.clear();
      s.replenishQueue();

      expect(s.queue.comparisonCount(), greaterThan(0),
          reason: 'a board with no comparisons must be resupplied');
    });

    test('a restock never fills the whole row with operators', () {
      // Committing eight operators at once would drop a wall of them into the
      // board with no chance of spacing them out.
      final s = session(seed: 8);
      s.queue.clear();
      s.replenishQueue();

      expect(s.queue.operatorCount(),
          lessThanOrEqualTo(GameSession.maxOperatorBurst));
    });

    test('operators go to the least crowded columns', () {
      final s = session(seed: 9);
      // Pack column 0 with operators and leave column 7 clear of them.
      for (var y = 0; y < 8; y++) {
        s.board.set(0, y, s.generator.nextComparison());
        s.board.set(7, y, s.generator.nextDigit());
        s.board.set(6, y, s.generator.nextDigit());
      }
      s.queue.clear();
      s.replenishQueue();

      final operatorColumns = [
        for (var x = 0; x < s.queue.width; x++)
          if (isOperator(s.queue.peek(x))) x,
      ];
      expect(operatorColumns, isNot(contains(0)),
          reason: 'column 0 is already full of operators');
    });

    test('bombs are visible in the preview before they land', () {
      final s = session(seed: 7, bombChance: 1);
      for (var x = 0; x < 8; x++) {
        s.board.set(x, 0, s.generator.nextComparison());
        s.board.set(x, 2, s.generator.nextComparison());
      }
      s.queue.clear();
      s.replenishQueue();

      expect(s.queue.bombCount(), greaterThan(0));
      expect(
        s.queue.bombCount(),
        lessThanOrEqualTo(GameSession.maxBombsOnBoard),
      );
    });
  });
}
