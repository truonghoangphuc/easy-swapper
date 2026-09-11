import 'package:easy_swapper/core/board/board_model.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_helpers.dart';

void main() {
  group('findMatches', () {
    test('finds a horizontal match', () {
      final board = boardFrom([
        '1=1447',
        '937286',
        '452396',
        '681745',
      ]);
      final matches = board.findMatches();
      expect(matches.where((m) => m.horizontal && m.line == 0), hasLength(1));
      expect(matches.first.equation.cells.join(), '1=1');
    });

    test('finds a vertical match', () {
      final board = boardFrom([
        '2937',
        '=486',
        '2735',
        '9164',
      ]);
      final vertical = board.findMatches().where((m) => !m.horizontal).toList();
      expect(vertical, hasLength(1));
      expect(vertical.single.line, 0, reason: 'column 0 reads 2, =, 2');
      expect(vertical.single.cells, [
        const Coord(0, 0),
        const Coord(0, 1),
        const Coord(0, 2),
      ]);
    });

    test('a special tile cannot be consumed by an equation', () {
      final board = boardFrom([
        '1=1447',
        '937286',
        '452396',
        '681745',
      ]);
      expect(board.findMatches(), isNotEmpty);

      // Replace the middle of the run with a bomb; the run must stop matching.
      board.set(
        1,
        0,
        const Tile(
          id: 999,
          glyph: '\u{1F4A3}',
          kind: TileKind.special,
          special: SpecialKind.bomb,
        ),
      );
      expect(
        board.findMatches().where((m) => m.horizontal && m.line == 0),
        isEmpty,
      );
    });
  });

  group('findMatchesAffectedBy', () {
    test('scans only the two rows and two columns of the swap', () {
      final board = boardFrom([
        '1=1447',
        '937286',
        '452396',
        '681745',
      ]);
      // The row 0 match exists, but a swap far away must not report it.
      final near = board.findMatchesAffectedBy(const Coord(0, 0), const Coord(1, 0));
      expect(near, isNotEmpty);

      final far = board.findMatchesAffectedBy(const Coord(3, 3), const Coord(4, 3));
      expect(far.any((m) => m.horizontal && m.line == 0), isFalse);
    });
  });

  group('cellsToClear', () {
    test('unions overlapping row and column matches', () {
      // Column 0 and row 0 both read 1=1 and share the corner cell.
      final board = boardFrom([
        '1=1447',
        '=37286',
        '152396',
        '681745',
      ]);
      final cells = board.cellsToClear(board.findMatches());
      expect(cells, contains(const Coord(0, 0)));
      expect(cells, contains(const Coord(2, 0)));
      expect(cells, contains(const Coord(0, 2)));
      expect(cells.length, 5, reason: 'three per run, sharing the corner');
    });

    test('drags the other half of a fused comparison operator along', () {
      // Column 1 reads 3, <, 4 vertically. The < renders fused with the = to
      // its right, so clearing the < must clear that = too.
      final board = boardFrom([
        '2379',
        '9<=6',
        '5482',
        '6135',
      ]);
      final vertical = board.findMatches().where((m) => !m.horizontal).toList();
      expect(vertical, isNotEmpty, reason: 'column 1 reads 3 < 4');

      final cells = board.cellsToClear(vertical);
      expect(cells, contains(const Coord(1, 1)), reason: 'the < itself');
      expect(cells, contains(const Coord(2, 1)), reason: 'the fused =');
    });
  });

  group('compact', () {
    test('slides tiles down into the holes beneath them', () {
      final board = boardFrom([
        '12',
        '34',
        '56',
      ]);
      final top = board.at(0, 0)!;
      board.clear([const Coord(0, 1), const Coord(0, 2)]);

      final falls = board.compact();

      expect(board.at(0, 2), same(top), reason: 'the survivor lands on the floor');
      expect(board.at(0, 0), isNull);
      expect(board.at(0, 1), isNull);
      expect(falls, hasLength(1));
      expect(falls.single.from, const Coord(0, 0));
      expect(falls.single.to, const Coord(0, 2));
    });

    test('preserves order within a column and leaves other columns alone', () {
      final board = boardFrom([
        '12',
        '34',
        '56',
      ]);
      board.clear([const Coord(0, 1)]);
      board.compact();

      expect(board.at(0, 1)!.glyph, '1');
      expect(board.at(0, 2)!.glyph, '5');
      expect(board.at(1, 0)!.glyph, '2', reason: 'column 1 untouched');
    });

    test('reports nothing when there is nothing to move', () {
      final board = boardFrom(['12', '34']);
      expect(board.compact(), isEmpty);
    });
  });

  group('refill', () {
    test('fills every hole and reports the drop distance', () {
      final board = boardFrom([
        '12',
        '34',
      ]);
      board.clear([const Coord(0, 0), const Coord(0, 1)]);
      board.compact();

      var counter = 0;
      final spawns = board.refill(
        (_) => Tile(id: 100 + counter++, glyph: '7', kind: TileKind.digit),
      );

      expect(board.hasEmptyCells, isFalse);
      expect(spawns, hasLength(2));
      expect(spawns.map((s) => s.to), [const Coord(0, 1), const Coord(0, 0)]);
      // Both travel 2: the pair enters stacked above the board and falls in
      // formation, so the leading tile goes deeper but no further.
      expect(spawns.map((s) => s.dropDistance), [2, 2]);
    });
  });

  group('swap', () {
    test('exchanges two cells and is its own inverse', () {
      final board = boardFrom(['12', '34']);
      final a = board.at(0, 0)!;
      final b = board.at(1, 0)!;

      board.swap(const Coord(0, 0), const Coord(1, 0));
      expect(board.at(0, 0), same(b));
      expect(board.at(1, 0), same(a));

      board.swap(const Coord(0, 0), const Coord(1, 0));
      expect(board.at(0, 0), same(a));
      expect(board.at(1, 0), same(b));
    });
  });

  group('fromJson repairs a save it cannot trust', () {
    test('duplicate tile ids are reissued', () {
      // Tile ids key the render layer's components, so two cells sharing one
      // id means two cells sharing one component - a view that can never agree
      // with the model again. Saves written by earlier builds really do
      // contain these: the generator used to restart its counter at zero on
      // restore while the board kept the saved one.
      final board = boardFrom(['12', '34']);
      final json = board.toJson();
      final grid = json['grid'] as List;
      final topLeft = (grid[0] as List)[0] as Map<String, dynamic>;
      final bottomLeft = (grid[1] as List)[0] as Map<String, dynamic>;
      // Force a collision: bottom-left now carries the same id as top-left.
      bottomLeft['id'] = topLeft['id'];

      final restored = BoardModel.fromJson(json);
      final ids = restored.tiles.map((t) => t.id).toList();

      expect(ids.toSet(), hasLength(ids.length), reason: 'still duplicated');
      expect(restored.tiles, hasLength(4), reason: 'no tile was dropped');
      expect(
        restored.debugString(),
        board.debugString(),
        reason: 'only the id was repaired, not the glyph',
      );
    });

    test('the id counter is lifted above everything on the board', () {
      final board = boardFrom(['12', '34']);
      final json = board.toJson();
      // A counter that lags the grid - the shape a partial write leaves.
      (json['ids'] as Map<String, dynamic>)['next'] = 0;

      final restored = BoardModel.fromJson(json);
      final highest =
          restored.tiles.map((t) => t.id).reduce((a, b) => a > b ? a : b);
      expect(restored.ids.nextId(), greaterThan(highest));
    });
  });

  group('allSwapPairs', () {
    test('lists every orthogonal pair exactly once', () {
      final board = boardFrom(['12', '34']);
      // A 2x2 board has two horizontal and two vertical pairs.
      expect(board.allSwapPairs(), hasLength(4));
    });

    test('scales as expected on the default board', () {
      final board = BoardModel(width: 8, height: 8);
      expect(board.allSwapPairs(), hasLength(2 * 8 * 7));
    });
  });

  group('Coord', () {
    test('adjacency is orthogonal only', () {
      expect(const Coord(1, 1).isAdjacentTo(const Coord(1, 2)), isTrue);
      expect(const Coord(1, 1).isAdjacentTo(const Coord(2, 1)), isTrue);
      expect(const Coord(1, 1).isAdjacentTo(const Coord(2, 2)), isFalse,
          reason: 'diagonal');
      expect(const Coord(1, 1).isAdjacentTo(const Coord(1, 1)), isFalse);
    });

    test('is usable as a set key', () {
      const a = Coord(1, 2);
      final b = Coord(1, 1 + 1);
      expect({a, b}, hasLength(1));
    });
  });
}
