/// The grid, and every mutation the game performs on it. Pure Dart.
library;

import '../math/expression_engine.dart';
import 'tile.dart';

/// Produces a fresh tile for the refill slot at the given coordinate.
///
/// The coordinate matters: whether an operator may be placed depends on what is
/// already sitting next to that cell.
typedef TileFactory = Tile Function(Coord at);

/// One equation found on the board, located in grid space.
class BoardMatch {
  const BoardMatch({
    required this.horizontal,
    required this.line,
    required this.equation,
  });

  /// True for a row match, false for a column match.
  final bool horizontal;

  /// The row index for a horizontal match, the column index for a vertical one.
  final int line;

  final EquationMatch equation;

  int get score => equation.score;

  /// The cells this match occupies, in reading order.
  List<Coord> get cells => [
        for (var i = equation.start; i <= equation.end; i++)
          horizontal ? Coord(i, line) : Coord(line, i),
      ];

  @override
  String toString() =>
      '${horizontal ? "row" : "col"} $line ${equation.cells.join()} = $score';
}

/// A tile moving from one cell to another during compaction.
class TileFall {
  const TileFall(this.tile, this.from, this.to);

  final Tile tile;
  final Coord from;
  final Coord to;
}

/// A tile entering the board from above during refill.
class TileSpawn {
  const TileSpawn(this.tile, this.to, this.dropDistance);

  final Tile tile;
  final Coord to;

  /// How many cells above the board the tile starts, so the render layer can
  /// stagger the drop.
  final int dropDistance;
}

/// A mutable grid of tiles.
///
/// Indexing is `[y][x]` with y increasing downward, matching easy-mathriss.
/// A `null` cell only ever exists transiently, between a clear and a refill.
class BoardModel {
  BoardModel({required this.width, required this.height, TileIdGenerator? ids})
      : ids = ids ?? TileIdGenerator(),
        _grid = List.generate(
          height,
          (_) => List<Tile?>.filled(width, null),
          growable: false,
        );

  final int width;
  final int height;
  final TileIdGenerator ids;
  final List<List<Tile?>> _grid;

  Tile? at(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return null;
    return _grid[y][x];
  }

  Tile? atCoord(Coord c) => at(c.x, c.y);

  void set(int x, int y, Tile? tile) {
    _grid[y][x] = tile;
  }

  void setCoord(Coord c, Tile? tile) => set(c.x, c.y, tile);

  bool get hasEmptyCells =>
      _grid.any((row) => row.any((tile) => tile == null));

  /// Every tile currently on the board, row by row.
  List<Tile> get tiles => [
        for (final row in _grid)
          for (final tile in row) ?tile,
      ];

  /// Row [y] as scannable glyphs.
  List<String?> row(int y) => [for (var x = 0; x < width; x++) at(x, y)?.scanGlyph];

  /// Column [x] as scannable glyphs.
  List<String?> column(int x) =>
      [for (var y = 0; y < height; y++) at(x, y)?.scanGlyph];

  /// Swaps two cells. Callers are responsible for checking adjacency.
  void swap(Coord a, Coord b) {
    final tmp = atCoord(a);
    setCoord(a, atCoord(b));
    setCoord(b, tmp);
  }

  /// Scans every row and column.
  List<BoardMatch> findMatches({int minRunLength = 3}) {
    final matches = <BoardMatch>[];
    for (var y = 0; y < height; y++) {
      for (final eq in findAllEquations(row(y), minRunLength: minRunLength)) {
        matches.add(BoardMatch(horizontal: true, line: y, equation: eq));
      }
    }
    for (var x = 0; x < width; x++) {
      for (final eq in findAllEquations(column(x), minRunLength: minRunLength)) {
        matches.add(BoardMatch(horizontal: false, line: x, equation: eq));
      }
    }
    return matches;
  }

  /// Scans only the rows and columns touched by [a] and [b].
  ///
  /// This is the swap-legality check, and it is the hot path: the solver calls
  /// it once per candidate swap, so it must not walk the whole board.
  List<BoardMatch> findMatchesAffectedBy(
    Coord a,
    Coord b, {
    int minRunLength = 3,
  }) {
    final matches = <BoardMatch>[];
    final rows = <int>{a.y, b.y};
    final cols = <int>{a.x, b.x};
    for (final y in rows) {
      for (final eq in findAllEquations(row(y), minRunLength: minRunLength)) {
        matches.add(BoardMatch(horizontal: true, line: y, equation: eq));
      }
    }
    for (final x in cols) {
      for (final eq in findAllEquations(column(x), minRunLength: minRunLength)) {
        matches.add(BoardMatch(horizontal: false, line: x, equation: eq));
      }
    }
    return matches;
  }

  /// The union of every cell covered by [matches], plus any dangling half of a
  /// fused comparison operator.
  ///
  /// Two adjacent cells such as `<` and `=` render as a single `<=` glyph. A
  /// vertical match can clear the `<` while leaving the `=` behind, which would
  /// show the player half an operator. easy-mathriss solves this the same way,
  /// in `Board.checkMathMatches`.
  Set<Coord> cellsToClear(List<BoardMatch> matches) {
    final cells = <Coord>{};
    for (final match in matches) {
      cells.addAll(match.cells);
    }

    final expanded = <Coord>{};
    for (final c in cells) {
      final glyph = atCoord(c)?.glyph;
      if (glyph == '<' || glyph == '>' || glyph == '!') {
        if (at(c.x + 1, c.y)?.glyph == '=') expanded.add(Coord(c.x + 1, c.y));
      } else if (glyph == '=') {
        final left = at(c.x - 1, c.y)?.glyph;
        if (left == '<' || left == '>' || left == '!') {
          expanded.add(Coord(c.x - 1, c.y));
        }
      }
    }
    return cells..addAll(expanded);
  }

  /// Every occupied cell destroyed by detonating a bomb at [origin]: its whole
  /// row and its whole column, a cross.
  ///
  /// Other bombs caught in the blast come back like any other cell. Whether
  /// they chain is the session's decision, not the model's.
  Set<Coord> blastCells(Coord origin) {
    final cells = <Coord>{};
    for (var x = 0; x < width; x++) {
      if (at(x, origin.y) != null) cells.add(Coord(x, origin.y));
    }
    for (var y = 0; y < height; y++) {
      if (at(origin.x, y) != null) cells.add(Coord(origin.x, y));
    }
    return cells;
  }

  /// How many cells hold an arithmetic or comparison glyph.
  int operatorCount() {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isOperator(at(x, y))) count++;
      }
    }
    return count;
  }

  /// Every cell currently empty, in reading order.
  List<Coord> emptyCells() => [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            if (at(x, y) == null) Coord(x, y),
      ];

  /// How many cells hold a comparison glyph.
  ///
  /// Tracked separately from [operatorCount] because comparisons are the
  /// resource the board can actually run out of: every match consumes exactly
  /// one, and `+` or `-` cannot substitute.
  int comparisonCount() {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (at(x, y)?.kind == TileKind.comparison) count++;
      }
    }
    return count;
  }

  /// How many orthogonal neighbours of [at] hold an operator.
  ///
  /// Used while filling, so cells that are still empty simply do not count.
  int operatorNeighbourCount(Coord at) {
    var count = 0;
    if (isOperator(this.at(at.x - 1, at.y))) count++;
    if (isOperator(this.at(at.x + 1, at.y))) count++;
    if (isOperator(this.at(at.x, at.y - 1))) count++;
    if (isOperator(this.at(at.x, at.y + 1))) count++;
    return count;
  }

  /// True if any orthogonal neighbour of [at] already holds an operator.
  bool hasOperatorNeighbour(Coord at) => operatorNeighbourCount(at) > 0;

  /// Coordinates of every operator with an operator orthogonally beside it.
  List<Coord> adjacentOperators() => [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            if (isOperator(at(x, y)) && hasOperatorNeighbour(Coord(x, y)))
              Coord(x, y),
      ];

  /// Coordinates of every bomb currently on the board.
  List<Coord> bombCells() => [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            if (at(x, y)?.isBomb ?? false) Coord(x, y),
      ];

  /// Empties [cells].
  void clear(Iterable<Coord> cells) {
    for (final c in cells) {
      setCoord(c, null);
    }
  }

  /// Slides every tile down into the holes beneath it.
  ///
  /// Returns the movements so the render layer can animate them. Ported from
  /// the `emptySpot` walker in `easy-mathriss/lib/game/components/board.dart`.
  List<TileFall> compact() {
    final falls = <TileFall>[];
    for (var x = 0; x < width; x++) {
      var emptySpot = height - 1;
      for (var y = height - 1; y >= 0; y--) {
        final tile = at(x, y);
        if (tile == null) continue;
        if (y != emptySpot) {
          set(x, emptySpot, tile);
          set(x, y, null);
          falls.add(TileFall(tile, Coord(x, y), Coord(x, emptySpot)));
        }
        emptySpot--;
      }
    }
    return falls;
  }

  /// Fills every empty cell from [factory], top-down per column.
  List<TileSpawn> refill(TileFactory factory) {
    final spawns = <TileSpawn>[];
    for (var x = 0; x < width; x++) {
      var dropDistance = 1;
      for (var y = height - 1; y >= 0; y--) {
        if (at(x, y) != null) continue;
        final tile = factory(Coord(x, y));
        set(x, y, tile);
        spawns.add(TileSpawn(tile, Coord(x, y), dropDistance));
        dropDistance++;
      }
    }
    return spawns;
  }

  /// Every orthogonal cell pair on the board, each listed once.
  List<(Coord, Coord)> allSwapPairs() {
    final pairs = <(Coord, Coord)>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (x + 1 < width) pairs.add((Coord(x, y), Coord(x + 1, y)));
        if (y + 1 < height) pairs.add((Coord(x, y), Coord(x, y + 1)));
      }
    }
    return pairs;
  }

  /// A deep copy sharing the same tile instances (tiles are immutable).
  BoardModel copy() {
    final clone = BoardModel(width: width, height: height, ids: ids);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        clone.set(x, y, at(x, y));
      }
    }
    return clone;
  }

  /// Renders the grid as text, one row per line. Debug and test aid.
  String debugString() => [
        for (var y = 0; y < height; y++)
          [for (var x = 0; x < width; x++) at(x, y)?.glyph ?? '.'].join(' '),
      ].join('\n');
}
