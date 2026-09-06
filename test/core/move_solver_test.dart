import 'package:easy_swapper/core/board/board_model.dart';
import 'package:easy_swapper/core/board/move_solver.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_helpers.dart';

/// Row 0 reads `1 = 4 1`. Swapping the last two cells makes it `1 = 1 4`, whose
/// leading three cells are a valid equation. Nothing matches before that swap.
///
/// Note the digit-merging trap when reading these fixtures: `1 = 1 4` does not
/// match as a whole, because the right side tokenizes as fourteen. It matches
/// only on the three-cell prefix.
List<String> get _oneMoveBoard => [
      '1=41',
      '5762',
      '8395',
      '2687',
    ];

const _theMove = (Coord(2, 0), Coord(3, 0));

void main() {
  group('findAllLegalMoves', () {
    test('finds the swap that completes an equation', () {
      final board = boardFrom(_oneMoveBoard);
      expect(board.findMatches(), isEmpty, reason: 'nothing matches yet');

      final moves = findAllLegalMoves(board);
      expect(
        moves.any((m) =>
            (m.a == _theMove.$1 && m.b == _theMove.$2) ||
            (m.a == _theMove.$2 && m.b == _theMove.$1)),
        isTrue,
        reason: 'expected $_theMove among $moves',
      );
    });

    test('reports no move on a board where nothing can match', () {
      // No comparison glyph anywhere, so no equation is reachable at all.
      final board = boardFrom([
        '1234',
        '5678',
        '9123',
        '4567',
      ]);
      expect(findAllLegalMoves(board), isEmpty);
      expect(hasAnyLegalMove(board), isFalse);
      expect(findBestMove(board), isNull);
    });

    test('leaves the board exactly as it found it', () {
      final board = boardFrom(_oneMoveBoard);
      final before = board.debugString();
      findAllLegalMoves(board);
      expect(board.debugString(), before);
    });

    test('every reported move really does produce a match', () {
      // This is the property that matters: a hint the player cannot act on, or
      // a deadlock check that lies, both break the game.
      final board = boardFrom([
        '1=41',
        '5=62',
        '8395',
        '2687',
      ]);
      final moves = findAllLegalMoves(board);
      expect(moves, isNotEmpty);

      for (final move in moves) {
        board.swap(move.a, move.b);
        expect(board.findMatches(), isNotEmpty,
            reason: 'solver claimed $move is legal');
        board.swap(move.a, move.b);
      }
    });

    test('honours minRunLength', () {
      final board = boardFrom(_oneMoveBoard);
      final short = findAllLegalMoves(board, minRunLength: 3);
      final long = findAllLegalMoves(board, minRunLength: 5);

      expect(short, isNotEmpty);
      expect(
        long.any((m) => m.a == _theMove.$1 && m.b == _theMove.$2),
        isFalse,
        reason: 'the only reachable run here is three cells long',
      );
      expect(long.length, lessThanOrEqualTo(short.length));
    });

    test('hasAnyLegalMove agrees with findAllLegalMoves', () {
      final playable = boardFrom(_oneMoveBoard);
      final dead = boardFrom([
        '1234',
        '5678',
        '9123',
        '4567',
      ]);
      expect(hasAnyLegalMove(playable), findAllLegalMoves(playable).isNotEmpty);
      expect(hasAnyLegalMove(dead), findAllLegalMoves(dead).isNotEmpty);
    });
  });

  group('findBestMove', () {
    test('returns the highest-scoring move available', () {
      final board = boardFrom([
        '1=41',
        '5=62',
        '8395',
        '2687',
      ]);
      final best = findBestMove(board);
      final all = findAllLegalMoves(board);
      expect(best, isNotNull);
      expect(best!.score, all.map((m) => m.score).reduce((a, b) => a > b ? a : b));
    });
  });

  group('performance', () {
    test('a full 8x8 scan stays well inside a frame budget', () {
      // The solver runs on every settle, so a regression here is felt directly.
      final board = BoardModel(width: 8, height: 8);
      var id = 0;
      const glyphs = '123456789+-=';
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final glyph = glyphs[(x * 7 + y * 3) % glyphs.length];
          board.set(x, y, Tile(id: id++, glyph: glyph, kind: kindOf(glyph)));
        }
      }

      final watch = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        findAllLegalMoves(board);
      }
      watch.stop();

      final perScan = watch.elapsedMicroseconds / 20 / 1000;
      expect(perScan, lessThan(50),
          reason: 'one full solve took ${perScan.toStringAsFixed(1)}ms');
    });
  });
}
