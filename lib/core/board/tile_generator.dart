/// Weighted tile generation, board seeding, and reshuffling. Pure Dart.
///
/// A uniform draw over ten digits and the operator set produces a board with
/// almost no findable equations, so the distribution is deliberately skewed:
/// small digits combine into valid sums far more often than large ones, and
/// comparison glyphs are the bottleneck resource because every single match
/// consumes exactly one.
///
/// Two hard rules bound the draw, both enforced on the board rather than left
/// to chance, because a weighted draw only hits its shares on average:
///
///   * operators never exceed [operatorCapFraction] of the cells
///   * two operators are never generated orthogonally adjacent
///
/// Comparison takes roughly two thirds of the operator budget. The split was
/// swept in `tool/tune_weights.dart`, and the two ends of it pull against each
/// other: comparison drives how many legal moves exist (every match consumes
/// exactly one), while arithmetic drives how interesting they are (with too few
/// `+` and `-`, almost every match degenerates to `N=N`). At 65/35 the tiers sit
/// at 9.5 to 11.5 opening moves and the hardest configuration - tier 2 needing
/// five-cell runs - still holds 8.3.
///
/// Re-run `tool/tune_weights.dart` after any change here, to the matching rules,
/// or to the board size.
library;

import 'dart:math';

import '../levels/level_def.dart';
import 'board_model.dart';
import 'move_solver.dart';
import 'tile.dart';

/// Relative frequency of each glyph category.
class TileWeights {
  const TileWeights({
    this.digitShare = 0.670,
    this.arithmeticShare = 0.115,
    this.comparisonShare = 0.215,
  });

  final double digitShare;
  final double arithmeticShare;
  final double comparisonShare;

  /// Within-category weights. Low digits are twice as likely as high ones, and
  /// zero is held down because it leads to dead division and leading zeros.
  static const Map<String, double> digitWeights = {
    '0': 1,
    '1': 2,
    '2': 2,
    '3': 2,
    '4': 2,
    '5': 2,
    '6': 1,
    '7': 1,
    '8': 1,
    '9': 1,
  };

  static const Map<String, double> arithmeticWeights = {
    '+': 3,
    '-': 3,
    '*': 1,
    '/': 1,
    '^': 1,
  };

  static const Map<String, double> comparisonWeights = {
    '=': 4,
    '<': 1,
    '>': 1,
    '!': 1,
  };
}

/// Thrown when the generator cannot produce a playable board.
///
/// Reaching this is a bug in the weights or the level configuration, not a
/// runtime condition to recover from, so it fails loudly rather than handing
/// back an unplayable grid.
class BoardGenerationException implements Exception {
  BoardGenerationException(this.message);

  final String message;

  @override
  String toString() => 'BoardGenerationException: $message';
}

/// Draws weighted tiles and builds boards that are guaranteed playable.
class TileGenerator {
  TileGenerator({
    required this.operators,
    required this.ids,
    Random? rng,
    this.weights = const TileWeights(),
    this.bombChance = defaultBombChance,
  }) : rng = rng ?? Random() {
    _buildTable();
  }

  /// Chance a refilled cell arrives as a bomb.
  ///
  /// Low on purpose. A bomb does not tokenize, so every one sitting on the
  /// board is a hole in the equations the player can still form; too many and
  /// the game stops being about arithmetic.
  static const double defaultBombChance = 0.03;

  /// Ceiling on operators, as a fraction of the board.
  ///
  /// Operators cannot start or end an equation and cannot sit beside each other,
  /// so past roughly a third of the cells they stop enabling runs and start
  /// crowding out the digits those runs need.
  static const double operatorCapFraction = 1 / 3;

  /// Floor on comparison glyphs, as a fraction of the board.
  ///
  /// Without this the game bleeds out. Every match consumes a comparison, but
  /// roughly half of all refill slots sit next to an existing operator and so
  /// cannot take one - measured with `dart run tool/tune_weights.dart playout`,
  /// runs were dying of deadlock after about eight moves. Below this floor a
  /// refill is forced to hand back a comparison even if that puts two operators
  /// side by side; keeping the board playable beats keeping the layout tidy.
  static const double comparisonFloorFraction = 0.19;

  /// Floor on operators of any kind, as a fraction of the board.
  ///
  /// Longer runs need two operators inside one window - `_ + _ = _` - so the
  /// board has to hold a working stock, not merely stay under the cap.
  static const double operatorFloorFraction = 0.23;

  final OperatorSet operators;
  final TileIdGenerator ids;
  final Random rng;
  final TileWeights weights;
  final double bombChance;

  final List<String> _glyphs = [];
  final List<TileKind> _kinds = [];
  final List<double> _cumulative = [];
  double _total = 0;

  /// The table is laid out digits, then arithmetic, then comparisons, so a
  /// category-only draw is a roll against one contiguous slice of it.
  int _digitCount = 0;
  double _digitTotal = 0;
  int _comparisonStart = 0;

  void _buildTable() {
    void addCategory(
      Map<String, double> table,
      Iterable<String> allowed,
      TileKind kind,
      double share,
    ) {
      final present = allowed.where(table.containsKey).toList();
      if (present.isEmpty) return;
      final sum = present.fold<double>(0, (s, g) => s + table[g]!);
      for (final glyph in present) {
        _total += share * (table[glyph]! / sum);
        _glyphs.add(glyph);
        _kinds.add(kind);
        _cumulative.add(_total);
      }
    }

    addCategory(
      TileWeights.digitWeights,
      TileWeights.digitWeights.keys,
      TileKind.digit,
      weights.digitShare,
    );
    _digitCount = _glyphs.length;
    _digitTotal = _total;

    addCategory(
      TileWeights.arithmeticWeights,
      operators.arithmetic,
      TileKind.arithmetic,
      weights.arithmeticShare,
    );
    _comparisonStart = _glyphs.length;
    addCategory(
      TileWeights.comparisonWeights,
      operators.comparison,
      TileKind.comparison,
      weights.comparisonShare,
    );
  }

  /// One weighted random tile.
  Tile next() {
    final roll = rng.nextDouble() * _total;
    var index = 0;
    while (index < _cumulative.length - 1 && roll > _cumulative[index]) {
      index++;
    }
    return Tile(id: ids.nextId(), glyph: _glyphs[index], kind: _kinds[index]);
  }

  /// One tile for a refill slot, which may arrive as a bomb.
  ///
  /// Kept separate from [next] on purpose: board generation must never place a
  /// bomb, both because a free power-up on the opening board is a gift and
  /// because bombs do not tokenize, so seeding them would skew the move counts
  /// `tool/tune_weights.dart` measures.
  Tile nextRefillTile({bool allowBomb = true, bool allowOperator = true}) {
    if (allowBomb && rng.nextDouble() < bombChance) {
      return Tile.bomb(ids.nextId());
    }
    // Wildcards appear rarely — roughly one per three boards on average.
    if (allowBomb && rng.nextDouble() < 0.015) {
      return Tile.wildcard(ids.nextId());
    }
    return allowOperator ? next() : nextDigit();
  }

  /// A weighted digit, never an operator.
  ///
  /// Used wherever the operator budget is spent or the cell has an operator
  /// beside it already.
  Tile nextDigit() {
    final roll = rng.nextDouble() * _digitTotal;
    var index = 0;
    while (index < _digitCount - 1 && roll > _cumulative[index]) {
      index++;
    }
    return Tile(id: ids.nextId(), glyph: _glyphs[index], kind: TileKind.digit);
  }

  /// The most operators allowed on a [width] x [height] board.
  int operatorCapFor(int width, int height) =>
      (width * height * operatorCapFraction).floor();

  /// The fewest comparison glyphs a board should be left holding.
  ///
  /// A tier with only `=` needs more of them than one with `<` and `>`. An
  /// inequality between two random numbers is true about half the time, while
  /// equality almost never is, so the same count of comparison glyphs buys far
  /// fewer legal moves - which is why tier 1 was the tier that suffered most
  /// once the preview started committing tiles in advance.
  int comparisonFloorFor(int width, int height) {
    final hasInequality =
        operators.comparison.contains('<') || operators.comparison.contains('>');
    final fraction = hasInequality
        ? comparisonFloorFraction
        : comparisonFloorFraction * 1.35;
    final floor = (width * height * fraction).round();
    return floor < 3 ? 3 : floor;
  }

  /// The fewest operators of any kind a board should be left holding.
  int operatorFloorFor(int width, int height) =>
      (width * height * operatorFloorFraction).round();

  /// A weighted operator, arithmetic or comparison.
  Tile nextOperator() {
    final base = _digitTotal;
    final roll = base + rng.nextDouble() * (_total - base);
    var index = _digitCount;
    while (index < _cumulative.length - 1 && roll > _cumulative[index]) {
      index++;
    }
    return Tile(id: ids.nextId(), glyph: _glyphs[index], kind: _kinds[index]);
  }

  /// A weighted comparison glyph.
  ///
  /// Used to top the board up when it is running out of them; see
  /// [comparisonFloorFraction].
  Tile nextComparison() {
    final start = _comparisonStart;
    final base = start == 0 ? 0.0 : _cumulative[start - 1];
    final roll = base + rng.nextDouble() * (_total - base);
    var index = start;
    while (index < _cumulative.length - 1 && roll > _cumulative[index]) {
      index++;
    }
    return Tile(
      id: ids.nextId(),
      glyph: _glyphs[index],
      kind: TileKind.comparison,
    );
  }

  /// A tile for [at] that respects the operator budget and the no-adjacent rule.
  Tile _drawFor(BoardModel board, Coord at, int cap) {
    final allowOperator =
        board.operatorCount() < cap && !board.hasOperatorNeighbour(at);
    return allowOperator ? next() : nextDigit();
  }

  /// A tile carrying an explicit [glyph], used when planting a seed equation.
  Tile tileFor(String glyph) => Tile(
        id: ids.nextId(),
        glyph: glyph,
        kind: _kindOf(glyph),
      );

  TileKind _kindOf(String glyph) {
    if (TileWeights.digitWeights.containsKey(glyph)) return TileKind.digit;
    if (TileWeights.arithmeticWeights.containsKey(glyph)) {
      return TileKind.arithmetic;
    }
    return TileKind.comparison;
  }

  /// Replaces one cell of every equation on the board, and every operator that
  /// broke a composition rule, until nothing matches and the rules hold.
  ///
  /// Rejection sampling is the obvious approach and it does not work: on the
  /// inequality tiers roughly three in four random arrangements contain some
  /// match, because `a > b` is true half the time it appears. Repairing
  /// converges in a handful of passes where re-rolling would keep losing.
  ///
  /// Cells are *replaced*, not swapped. Swapping preserves the tile multiset but
  /// moves operators around, which undoes the adjacency work the same pass just
  /// did; drawing a fresh constrained tile fixes both at once.
  bool _repairBoard(
    BoardModel board,
    int minRunLength,
    int cap, {
    int maxPasses = 80,
  }) {
    for (var pass = 0; pass < maxPasses; pass++) {
      final offenders = _compositionOffenders(board, cap);
      for (final cell in offenders) {
        board.setCoord(cell, nextDigit());
      }

      final matches = board.findMatches(minRunLength: minRunLength);
      if (matches.isEmpty && offenders.isEmpty) return true;

      for (final match in matches) {
        final cells = match.cells;
        final victim = cells[rng.nextInt(cells.length)];
        board.setCoord(victim, _drawFor(board, victim, cap));
      }
    }
    return board.findMatches(minRunLength: minRunLength).isEmpty &&
        _compositionOffenders(board, cap).isEmpty;
  }

  /// Operators that must be demoted to digits: those sitting beside another
  /// operator, plus however many are over the budget.
  List<Coord> _compositionOffenders(BoardModel board, int cap) {
    final offenders = <Coord>[...board.adjacentOperators()];

    var over = board.operatorCount() - offenders.length - cap;
    if (over > 0) {
      for (var y = 0; y < board.height && over > 0; y++) {
        for (var x = 0; x < board.width && over > 0; x++) {
          final cell = Coord(x, y);
          if (!isOperator(board.atCoord(cell))) continue;
          if (offenders.contains(cell)) continue;
          offenders.add(cell);
          over--;
        }
      }
    }
    return offenders;
  }

  /// Builds a board that has no pre-existing match, holds the composition rules,
  /// and offers at least [minMoves] legal swaps.
  ///
  /// Tries plain constrained fills first. If the weights cannot reach the move
  /// floor on their own - which happens on the higher [minRunLength] levels,
  /// where matches are genuinely scarce - it falls back to planting one
  /// known-good equation and displacing a cell so the player has to swap it back.
  BoardModel generateBoard({
    required int width,
    required int height,
    int minRunLength = 3,
    int minMoves = 3,
    int maxAttempts = 50,
  }) {
    final cap = operatorCapFor(width, height);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final board = _randomBoard(width, height, cap);
      if (!_repairBoard(board, minRunLength, cap)) continue;
      if (findAllLegalMoves(board, minRunLength: minRunLength).length >= minMoves) {
        return board;
      }
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final board = _randomBoard(width, height, cap);
      if (!_plantSolvableEquation(board, minRunLength)) continue;
      // Planting can complete an equation elsewhere, and displacing a cell can
      // push two operators together; repair may in turn disturb the planted run,
      // so the move check below is still the real gate.
      if (!_repairBoard(board, minRunLength, cap)) continue;
      if (hasAnyLegalMove(board, minRunLength: minRunLength)) return board;
    }

    throw BoardGenerationException(
      'no playable ${width}x$height board after ${maxAttempts * 2} attempts '
      '(minRunLength $minRunLength, minMoves $minMoves)',
    );
  }

  BoardModel _randomBoard(int width, int height, int cap) {
    final board = BoardModel(width: width, height: height, ids: ids);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Filling in reading order means only the left and upper neighbours
        // exist yet, which is enough: adjacency is symmetric, so a pair can only
        // be created by the second of the two cells.
        board.set(x, y, _drawFor(board, Coord(x, y), cap));
      }
    }
    return board;
  }

  /// Writes a valid equation into a random row, then displaces one of its cells
  /// vertically so the equation is one swap away rather than already solved.
  ///
  /// Returns false if the board is too small or the row could not be placed;
  /// the caller retries.
  bool _plantSolvableEquation(BoardModel board, int minRunLength) {
    final glyphs = _buildEquation(minRunLength);
    if (glyphs.length > board.width || board.height < 2) return false;

    final y = rng.nextInt(board.height);
    final startX = rng.nextInt(board.width - glyphs.length + 1);
    for (var i = 0; i < glyphs.length; i++) {
      board.set(startX + i, y, tileFor(glyphs[i]));
    }

    // Displace one cell of the run into the row above or below, so swapping it
    // back restores the equation.
    final displaceX = startX + rng.nextInt(glyphs.length);
    final otherY = y + 1 < board.height ? y + 1 : y - 1;
    board.swap(Coord(displaceX, y), Coord(displaceX, otherY));
    return true;
  }

  /// A correct equation of at least [minRunLength] glyphs.
  ///
  /// Built as `a + b + ... = total` with a single-digit total, which keeps the
  /// length at `2k + 1` for k terms and works in every operator tier because
  /// `+` and `=` are always available.
  List<String> _buildEquation(int minRunLength) {
    final terms = max(1, ((minRunLength - 1) / 2).ceil());
    if (terms == 1) {
      final d = 1 + rng.nextInt(9);
      return ['$d', '=', '$d'];
    }

    // Pick `terms` values of at least 1 that sum to at most 9.
    final values = List<int>.filled(terms, 1);
    var remaining = 9 - terms;
    while (remaining > 0) {
      values[rng.nextInt(terms)]++;
      remaining--;
      if (rng.nextBool()) break;
    }

    final total = values.reduce((a, b) => a + b);
    final glyphs = <String>[];
    for (var i = 0; i < terms; i++) {
      if (i > 0) glyphs.add('+');
      glyphs.add('${values[i]}');
    }
    glyphs..add('=')..add('$total');
    return glyphs;
  }
}
