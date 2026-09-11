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
      // `scanGlyph`, not `glyph`: an encased `=` still *reads* as `=` to the
      // player, but it never fused into the match, so clearing it would take a
      // brick the equation never used.
      final glyph = atCoord(c)?.scanGlyph;
      if (glyph == '<' || glyph == '>' || glyph == '!') {
        if (at(c.x + 1, c.y)?.scanGlyph == '=') {
          expanded.add(Coord(c.x + 1, c.y));
        }
      } else if (glyph == '=') {
        final left = at(c.x - 1, c.y)?.scanGlyph;
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

  /// How many cells hold an arithmetic or comparison glyph, encased included.
  ///
  /// This is the *cap* figure. A brick under stone still occupies its cell and
  /// will one day be an operator, so every crowding rule has to see it.
  int operatorCount() {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isOperator(at(x, y))) count++;
      }
    }
    return count;
  }

  /// How many operators the player could actually build a run through.
  ///
  /// This is the *floor* figure, and the asymmetry with [operatorCount] is the
  /// point - the same split the preview queue already uses. The ceiling asks
  /// "is the board crowded"; the floor asks "is there anything left to play
  /// with", and an encased operator answers yes to the first and no to the
  /// second.
  int usableOperatorCount() {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (isUsableOperator(at(x, y))) count++;
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

  /// How many cells hold a comparison glyph the player can use.
  ///
  /// Tracked separately from [operatorCount] because comparisons are the
  /// resource the board can actually run out of: every match consumes exactly
  /// one, and `+` or `-` cannot substitute. Encased ones do not count, for the
  /// same reason they do not count toward [usableOperatorCount] - this number
  /// only ever feeds a floor.
  int comparisonCount() {
    var count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final tile = at(x, y);
        if (tile?.kind == TileKind.comparison && !tile!.isEncased) count++;
      }
    }
    return count;
  }

  /// How many usable comparison glyphs of each kind the board holds.
  ///
  /// Encased ones are left out for the same reason [comparisonCount] leaves
  /// them out: this feeds the supply rules, and a sealed glyph is no supply.
  Map<String, int> comparisonMix() {
    final mix = <String, int>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final tile = at(x, y);
        if (tile == null || tile.kind != TileKind.comparison) continue;
        if (tile.isEncased) continue;
        mix.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return mix;
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

  /// Operators in column [x] and in the columns either side of it.
  ///
  /// A queued tile is committed to a column before its row is known, so this is
  /// the best available guess at whether an operator dropped there would land
  /// next to another one.
  int columnCrowding(int x) {
    var count = 0;
    for (var col = x - 1; col <= x + 1; col++) {
      if (col < 0 || col >= width) continue;
      for (var y = 0; y < height; y++) {
        // Every row counts the same. Weighting the upper rows - where the holes
        // are, after a column compacts - looked like the better proxy and
        // measured worse: adjacency rose from 47% to 57%, because a queued tile
        // waits for its column and can land long after the shape that suggested
        // the weighting has gone.
        if (isOperator(at(col, y))) count++;
      }
    }
    return count;
  }

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

  /// Coordinates of every electric currently on the board.
  List<Coord> electricCells() => [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            if (at(x, y)?.isElectric ?? false) Coord(x, y),
      ];

  /// Coordinates of every encased brick, whatever depth of casing.
  List<Coord> encasedCells() => [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            if (at(x, y)?.isEncased ?? false) Coord(x, y),
      ];

  /// Coordinates of every brick no equation can currently run through.
  ///
  /// Bombs, electrics and encased bricks together. The session budgets these
  /// as one number: they are interchangeable as far as the board's remaining
  /// supply of legal moves is concerned, and per-type caps let the total drift
  /// until the board quietly stops offering anything.
  List<Coord> obstacleCells() => [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            if (at(x, y)?.isObstacle ?? false) Coord(x, y),
      ];

  /// Empties [cells].
  void clear(Iterable<Coord> cells) {
    for (final c in cells) {
      setCoord(c, null);
    }
  }

  /// Takes one layer of casing off each of [cells], leaving the brick in place.
  ///
  /// Returns the brick each cell is now holding - the tile itself, not just
  /// the depth it is down to. That matters: the render layer replays a step
  /// well after the model has compacted and refilled past it, so a cell
  /// coordinate no longer identifies the brick that was hit. Handing back the
  /// tile is what lets playback find the right component by id.
  ///
  /// Cells that are not encased are ignored.
  Map<Coord, Tile> damage(Iterable<Coord> cells) {
    final result = <Coord, Tile>{};
    for (final c in cells) {
      final tile = atCoord(c);
      if (tile == null || !tile.isEncased) continue;
      final next = tile.cracked();
      setCoord(c, next);
      result[c] = next;
    }
    return result;
  }

  /// Encased bricks orthogonally touching any of [cells].
  ///
  /// This is what turns a resolved equation into an impact: a run clearing
  /// beside a stone brick is what breaks it. A `Set` return is doing real work
  /// - a brick with three cleared neighbours still takes one hit, not three.
  Set<Coord> encasedNeighboursOf(Iterable<Coord> cells) {
    final hit = <Coord>{};
    for (final c in cells) {
      for (final n in [
        Coord(c.x - 1, c.y),
        Coord(c.x + 1, c.y),
        Coord(c.x, c.y - 1),
        Coord(c.x, c.y + 1),
      ]) {
        if (atCoord(n)?.isEncased ?? false) hit.add(n);
      }
    }
    return hit;
  }

  /// Every cell whose brick shows [glyph].
  ///
  /// Matches on the *visible* glyph, so an electric sweeping the board finds
  /// encased bricks too - what happens to them when it arrives is the
  /// session's decision, and it is damage rather than destruction.
  Set<Coord> cellsMatching(String glyph) {
    final cells = <Coord>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final tile = at(x, y);
        if (tile != null && !tile.isSpecial && tile.glyph == glyph) {
          cells.add(Coord(x, y));
        }
      }
    }
    return cells;
  }

  /// The glyph appearing on the most bricks, ignoring specials.
  ///
  /// The electric's fallback target for a partner that has no glyph of its own.
  /// Ties break on the lowest codepoint so a seeded run stays reproducible -
  /// iteration order alone would not guarantee that.
  String? mostCommonGlyph() {
    final counts = <String, int>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final tile = at(x, y);
        if (tile == null || tile.isSpecial) continue;
        counts.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    if (counts.isEmpty) return null;

    String? best;
    var bestCount = -1;
    for (final entry in counts.entries) {
      if (entry.value > bestCount ||
          (entry.value == bestCount &&
              best != null &&
              entry.key.compareTo(best) < 0)) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
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

  /// Fills every empty cell from [factory], bottom-up per column.
  ///
  /// Bottom-up is the physical order: the next tile to drop leads and settles
  /// deepest, and later ones stack above it. That order is what the next-drop
  /// preview promises, so it is not an implementation detail.
  List<TileSpawn> refill(TileFactory factory) {
    final spawns = <TileSpawn>[];
    for (var x = 0; x < width; x++) {
      var filled = 0;
      for (var y = height - 1; y >= 0; y--) {
        if (at(x, y) != null) continue;
        final tile = factory(Coord(x, y));
        set(x, y, tile);
        // Distance is measured from above the board, not from the cell: every
        // new tile enters over the top edge, so the one landing deepest travels
        // furthest. Measuring locally made them appear out of thin air part way
        // down the column.
        spawns.add(TileSpawn(tile, Coord(x, y), y + filled + 1));
        filled++;
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

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'ids': ids.toJson(),
        'grid': _grid
            .map((row) => row.map((tile) => tile?.toJson()).toList())
            .toList(),
      };

  factory BoardModel.fromJson(Map<String, dynamic> json) {
    final width = json['width'] as int;
    final height = json['height'] as int;
    final ids = TileIdGenerator.fromJson(json['ids'] as Map<String, dynamic>);
    final board = BoardModel(width: width, height: height, ids: ids);

    // Tile ids must be unique across the board: the render layer keys its
    // components by them, so a duplicate means two cells sharing one component
    // and a view that can never agree with the model again.
    //
    // Repaired here rather than trusted, because this is the boundary where
    // outside data comes in - and because saves written by earlier builds can
    // genuinely contain duplicates: the generator used to be handed a fresh id
    // counter on restore while the board kept the saved one, so every tile it
    // minted collided with one already in play.
    final seen = <int>{};
    final gridData = json['grid'] as List;
    for (var y = 0; y < height; y++) {
      final rowData = gridData[y] as List;
      for (var x = 0; x < width; x++) {
        if (rowData[x] == null) continue;
        var tile = Tile.fromJson(rowData[x] as Map<String, dynamic>);
        if (!seen.add(tile.id)) {
          tile = tile.copyWith(id: ids.nextId());
          seen.add(tile.id);
        }
        board.set(x, y, tile);
      }
    }

    // And the counter has to sit above everything on the board, however the
    // save got written.
    for (final id in seen) {
      if (id >= ids.current) ids.restore(id + 1);
    }
    return board;
  }
}
