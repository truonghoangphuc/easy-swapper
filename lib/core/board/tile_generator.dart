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
///   * operators never exceed [TileGenerator.operatorCapFraction] of the cells
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
/// The *split within* comparison is a difficulty dial rather than a constant.
/// See `lib/core/levels/difficulty_ramp.dart`: an endless run starts with `=`
/// dominant and widens toward `<` and `>` as the score climbs, because
/// equality almost never holds between two random numbers while an inequality
/// holds about half the time.
///
/// Re-run `tool/tune_weights.dart` after any change here, to the matching rules,
/// or to the board size.
library;

import 'dart:math';

import '../math/expression_engine.dart';
import '../levels/difficulty_ramp.dart';
import '../levels/level_def.dart';
import 'board_model.dart';
import 'move_solver.dart';
import 'tile.dart';

/// Relative frequency of each glyph category, and within each category.
class TileWeights {
  const TileWeights({
    this.digitShare = 0.670,
    this.arithmeticShare = 0.115,
    this.comparisonShare = 0.215,
    this.digitWeights = defaultDigitWeights,
    this.arithmeticWeights = defaultArithmeticWeights,
    this.comparisonWeights = defaultComparisonWeights,
  });

  final double digitShare;
  final double arithmeticShare;
  final double comparisonShare;

  /// Within-category weights, normalised over whatever glyphs the level's
  /// [OperatorSet] actually allows.
  ///
  /// That normalisation is worth stating, because it is where the `=` problem
  /// came from: `!` is absent from every shipped tier, so the historical
  /// `{'=': 4, '<': 1, '>': 1, '!': 1}` did not give `=` four sevenths of the
  /// comparison budget - it gave it four *sixths*.
  final Map<String, double> digitWeights;
  final Map<String, double> arithmeticWeights;
  final Map<String, double> comparisonWeights;

  /// Low digits are twice as likely as high ones, and zero is held down
  /// because it leads to dead division and leading zeros.
  static const Map<String, double> defaultDigitWeights = {
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

  static const Map<String, double> defaultArithmeticWeights = {
    '+': 3,
    '-': 3,
    '*': 1,
    '/': 1,
    '^': 1,
  };

  static const Map<String, double> defaultComparisonWeights = {
    '=': 4,
    '<': 1,
    '>': 1,
    '!': 1,
  };

  /// `=` as a fraction of the comparison glyphs [operators] actually allows.
  ///
  /// Drives the comparison floor: equality buys far fewer legal moves per
  /// glyph than an inequality does, so a board leaning on `=` has to hold more
  /// comparison tiles to stay alive.
  double equalityShareFor(OperatorSet operators) {
    var total = 0.0;
    var equality = 0.0;
    for (final glyph in operators.comparison) {
      final weight = comparisonWeights[glyph];
      if (weight == null) continue;
      total += weight;
      if (glyph == '=') equality += weight;
    }
    return total == 0 ? 1 : equality / total;
  }
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
    TileWeights? weights,
    DifficultyStage? stage,
    this.bombChance = defaultBombChance,
  })  : rng = rng ?? Random(),
        stage = stage ?? DifficultyStage.warmUp,
        weights =
            weights ?? (stage ?? DifficultyStage.warmUp).weights {
    _buildTable();
  }

  /// Chance a refilled cell arrives as a bomb.
  ///
  /// Low on purpose. A bomb does not tokenize, so every one sitting on the
  /// board is a hole in the equations the player can still form; too many and
  /// the game stops being about arithmetic.
  static const double defaultBombChance = 0.03;

  /// Chance a refilled cell arrives as a wildcard - roughly one per three
  /// boards. Unlike the other specials a wildcard *does* tokenize, so it is not
  /// a hole and is not counted against the obstacle budget.
  static const double wildcardChance = 0.015;

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

  /// The counter every new tile's id comes from.
  ///
  /// Not final: a restored session has to point this at the *board's* counter.
  /// A save stores the high-water mark alongside the grid, so a generator
  /// built fresh beside it starts again from zero and mints ids that collide
  /// with tiles already on the board. See [GameSession.fromJson].
  TileIdGenerator ids;

  final Random rng;
  final double bombChance;

  /// The current draw distribution. Replaced wholesale by [applyStage].
  TileWeights weights;

  /// Which rung of the difficulty ramp this generator is drawing for.
  ///
  /// Holds the obstacle budget as well as the weights, so the session can ask
  /// one object what this point of the run is allowed to produce.
  DifficultyStage stage;

  final List<String> _glyphs = [];
  final List<TileKind> _kinds = [];
  final List<double> _cumulative = [];
  double _total = 0;

  /// The table is laid out digits, then arithmetic, then comparisons, so a
  /// category-only draw is a roll against one contiguous slice of it.
  int _digitCount = 0;
  double _digitTotal = 0;
  int _comparisonStart = 0;

  /// Switches to [next]'s weights and obstacle budget.
  ///
  /// Rebuilding the table costs a handful of allocations and happens at most
  /// once per stage boundary - four times in a very long run.
  void applyStage(DifficultyStage next) {
    if (identical(next, stage)) return;
    stage = next;
    weights = next.weights;
    _buildTable();
  }

  void _buildTable() {
    _glyphs.clear();
    _kinds.clear();
    _cumulative.clear();
    _total = 0;
    _digitCount = 0;
    _digitTotal = 0;
    _comparisonStart = 0;

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
      weights.digitWeights,
      weights.digitWeights.keys,
      TileKind.digit,
      weights.digitShare,
    );
    _digitCount = _glyphs.length;
    _digitTotal = _total;

    addCategory(
      weights.arithmeticWeights,
      operators.arithmetic,
      TileKind.arithmetic,
      weights.arithmeticShare,
    );
    _comparisonStart = _glyphs.length;
    addCategory(
      weights.comparisonWeights,
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

  /// One tile for a refill slot, which may arrive as a power-up or encased.
  ///
  /// Kept separate from [next] on purpose: board generation must never place an
  /// obstacle, both because a free power-up on the opening board is a gift and
  /// because none of them tokenize, so seeding them would skew the move counts
  /// `tool/tune_weights.dart` measures.
  ///
  /// Every permit is decided by the caller against a board-wide budget, not
  /// here. This method only spends the dice.
  Tile nextRefillTile({
    bool allowBomb = true,
    bool allowOperator = true,
    bool allowElectric = false,
    bool allowWildcard = true,
    int maxCasing = Armor.none,
  }) {
    // Rarest first, so a stage that allows both does not have the bomb roll
    // swallow the electric's share.
    if (allowElectric && rng.nextDouble() < stage.electricChance) {
      return Tile.electric(ids.nextId());
    }
    if (allowBomb && rng.nextDouble() < bombChance) {
      return Tile.bomb(ids.nextId());
    }
    if (allowBomb && allowWildcard && rng.nextDouble() < wildcardChance) {
      return Tile.wildcard(ids.nextId());
    }

    final tile = allowOperator ? next() : nextDigit();
    return maybeEncase(tile, maxCasing: maxCasing);
  }

  /// Seals [tile] under a casing, if [maxCasing] allows and the dice agree.
  ///
  /// Specials are never encased: a bomb behind stone is a power-up the player
  /// cannot reach and cannot see the point of.
  Tile maybeEncase(Tile tile, {required int maxCasing}) {
    if (maxCasing <= Armor.none || tile.isSpecial) return tile;
    if (rng.nextDouble() >= stage.encasedChance) return tile;
    // A diamond is the rarer half of the casings that are allowed at all.
    final diamond = maxCasing >= Armor.diamond && rng.nextDouble() < 0.35;
    return tile.encased(diamond ? Armor.diamond : Armor.stone);
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
  /// A board leaning on `=` needs more of them than one with `<` and `>` in the
  /// mix. An inequality between two random numbers is true about half the time,
  /// while equality almost never is, so the same count of comparison glyphs
  /// buys far fewer legal moves.
  ///
  /// Scaled off the *weighted* share of `=` rather than off which glyphs the
  /// tier permits, because the difficulty ramp moves that share while the tier
  /// stays put - and it was tier 1, all equality, that suffered most when the
  /// preview started committing tiles in advance.
  int comparisonFloorFor(int width, int height) {
    final equality = weights.equalityShareFor(operators);
    // Calibrated so the two historical cases land exactly where they did: an
    // equality-only tier at 1.35x, and the old default 4:1:1 mix - which with
    // `!` absent came to two thirds equality - at 1.0x. A wider mix than that
    // scales below 1, clamped so a stage can never talk the floor away
    // entirely.
    const pivot = 2 / 3;
    final multiplier =
        (1 + 0.35 * (equality - pivot) / (1 - pivot)).clamp(0.80, 1.35);
    final floor = (width * height * comparisonFloorFraction * multiplier)
        .round();
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

  /// The target share of each comparison glyph this tier and stage allow.
  Map<String, double> comparisonTargets() {
    final table = weights.comparisonWeights;
    final present = operators.comparison.where(table.containsKey);
    final total = present.fold<double>(0, (sum, g) => sum + table[g]!);
    if (total == 0) return const {};
    return {for (final g in present) g: table[g]! / total};
  }

  /// A comparison glyph, nudged toward the stage's intended mix.
  ///
  /// [present] is what the board and queue are currently holding, by glyph.
  /// A glyph already at or above its share gets no boost; one below it gets a
  /// bounded one. See [DifficultyStage.comparisonCorrection] for why this is a
  /// nudge and not a correction, and why it is zero on the shipped levels.
  Tile nextComparisonFor(Map<String, int> present) {
    final correction = stage.comparisonCorrection;
    if (correction <= 0) return nextComparison();

    final targets = comparisonTargets();
    if (targets.length < 2) return nextComparison();

    final total = present.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return nextComparison();

    var sum = 0.0;
    final weights = <String, double>{};
    for (final entry in targets.entries) {
      final actual = (present[entry.key] ?? 0) / total;
      final shortfall = entry.value - actual;
      final weight =
          entry.value + (shortfall > 0 ? correction * shortfall : 0.0);
      weights[entry.key] = weight;
      sum += weight;
    }

    var roll = rng.nextDouble() * sum;
    for (final entry in weights.entries) {
      roll -= entry.value;
      if (roll <= 0) {
        return Tile(
          id: ids.nextId(),
          glyph: entry.key,
          kind: TileKind.comparison,
        );
      }
    }
    return nextComparison();
  }

  /// A tile for [at] that respects the operator budget and the no-adjacent rule.
  ///
  /// When [mix] is supplied, a comparison glyph is re-picked against it so the
  /// board is laid down on the stage's intended spread rather than relying on
  /// the draw to average out over sixty-four cells - which, being the whole of
  /// the sample, it does not.
  Tile _drawFor(BoardModel board, Coord at, int cap, [Map<String, int>? mix]) {
    final allowOperator =
        board.operatorCount() < cap && !board.hasOperatorNeighbour(at);
    final tile = allowOperator ? next() : nextDigit();
    if (mix == null || tile.kind != TileKind.comparison) return tile;

    final balanced = nextComparisonFor(mix);
    mix.update(balanced.glyph, (v) => v + 1, ifAbsent: () => 1);
    return balanced;
  }

  /// A tile carrying an explicit [glyph], used when planting a seed equation.
  Tile tileFor(String glyph) => Tile(
        id: ids.nextId(),
        glyph: glyph,
        kind: _kindOf(glyph),
      );

  /// Classifies a glyph.
  ///
  /// Reads the *default* tables, not the stage's: a stage may drop a glyph's
  /// weight to nothing, and that must not change what the glyph means.
  TileKind _kindOf(String glyph) {
    if (TileWeights.defaultDigitWeights.containsKey(glyph)) {
      return TileKind.digit;
    }
    if (TileWeights.defaultArithmeticWeights.containsKey(glyph)) {
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
        _breakMatch(board, match, minRunLength);
      }
    }
    return board.findMatches(minRunLength: minRunLength).isEmpty &&
        _compositionOffenders(board, cap).isEmpty;
  }

  /// Converts surplus comparison glyphs into the ones the board is short of,
  /// at whatever cells will take them without completing an equation.
  ///
  /// Repair is a one-way ratchet and this is the return path. Every rule in
  /// [_repairBoard] exists to stop equations being true, and a true equation
  /// is far more likely to be built on `<` or `>` than on `=` - so repair
  /// converts and deletes inequalities constantly while never once touching an
  /// `=`, which is never in a match to begin with. Left alone, a board drawn
  /// at 50% equals settles at 71%.
  ///
  /// Runs after repair has converged, so each rewrite only has to be checked
  /// against the two lines it touches and can simply be reverted if it
  /// completes something. Cells that cannot take an inequality keep their `=`:
  /// the board holds as many as it structurally can, which is the honest
  /// answer rather than a forced one.
  void _balanceComparisons(BoardModel board, int minRunLength) {
    if (stage.comparisonCorrection <= 0) return;
    final targets = comparisonTargets();
    if (targets.length < 2) return;

    for (var pass = 0; pass < 4; pass++) {
      final mix = board.comparisonMix();
      final total = mix.values.fold<int>(0, (a, b) => a + b);
      if (total == 0) return;

      double deficit(String g) => (targets[g] ?? 0) * total - (mix[g] ?? 0);
      final wanted = targets.keys.where((g) => deficit(g) >= 1).toList()
        ..sort((a, b) => deficit(b).compareTo(deficit(a)));
      if (wanted.isEmpty) return;

      var changed = false;
      for (var y = 0; y < board.height; y++) {
        for (var x = 0; x < board.width; x++) {
          if (wanted.isEmpty) break;
          final tile = board.at(x, y);
          if (tile == null || tile.kind != TileKind.comparison) continue;
          if (tile.isEncased) continue;
          if (deficit(tile.glyph) >= 0) continue; // not a surplus glyph

          final swapTo = wanted.first;
          board.set(x, y, tile.copyWith(glyph: swapTo));
          final safe = board
              .findMatchesAffectedBy(Coord(x, y), Coord(x, y),
                  minRunLength: minRunLength)
              .isEmpty;
          if (safe) {
            changed = true;
            wanted.removeAt(0);
          } else {
            board.set(x, y, tile);
          }
        }
      }
      if (!changed) return;
    }
  }

  /// Overwrites one cell of [match] so the statement stops being true.
  ///
  /// Prefers to spend a **digit**, never the comparison glyph. Picking at
  /// random looks fairer and is not: an inequality is true about half the time
  /// it appears while equality almost never is, so random repair destroys `<`
  /// and `>` far more often than `=` and leaves a board biased hard toward
  /// equality however the weights were set. Measured, random victims put `=`
  /// at 88% of the comparison glyphs on a board drawn from a 50% mix.
  ///
  /// The catch, and the reason this is not a one-liner: a *random* replacement
  /// digit often leaves the statement standing. Rewriting the 5 of `5 < 7` as
  /// a 2 changes nothing that matters, so the repair loop would find the same
  /// match again next pass. Left unchecked that cost twenty-five times the
  /// generation budget - six milliseconds a board became a hundred and forty.
  /// So the replacement is verified, and after a few failures the comparison
  /// glyph itself is spent, which always works.
  void _breakMatch(BoardModel board, BoardMatch match, int minRunLength) {
    final cells = match.cells;
    final digits = [
      for (final cell in cells)
        if (board.atCoord(cell)?.kind == TileKind.digit) cell,
    ];

    // Try different *positions*, not just different values. Re-rolling one
    // cell is not enough: in `12 < 99` no value at the leading digit can make
    // the statement false, so a loop that only re-rolls there always falls
    // through. Measured, that fallback was firing on half of all breaks - and
    // since inequalities are what mostly match, spending their comparison
    // glyph rebuilt the very bias this is here to avoid.
    for (var attempt = 0; attempt < 6 && digits.isNotEmpty; attempt++) {
      board.setCoord(digits[rng.nextInt(digits.length)], nextDigit());
      if (!_holds(board, match, minRunLength)) return;
    }

    // Nothing the digits can do. *Flip* the comparison rather than spend it:
    // `5 < 7` rewritten as `5 > 7` is false, and the board keeps the glyph.
    //
    // This is what finally settled the composition. Replacing the comparison
    // with a digit works too, and it was measured firing on half of all
    // breaks - which quietly destroyed inequalities at exactly the rate that
    // rebuilt the equality bias the draw weights were set to avoid. An
    // inequality is what usually forms a true statement, so it is what repair
    // usually has to undo; taking it off the board each time is how a 50% draw
    // became a 78% board.
    //
    // Only glyphs currently *below* their target share are eligible, and that
    // restriction is the load-bearing part. Repair only ever touches a glyph
    // sitting inside a true statement, and `=` almost never is - so a rule
    // that lets anything flip *to* `=` is a one-way ratchet with no return
    // path. Measured with plain deficit ordering: 105 flips landed on `=`
    // across forty boards, and the boards gained 104 of them, turning a 50%
    // draw into a 78% board.
    final comparison = cells.firstWhere(
      (c) => board.atCoord(c)?.kind == TileKind.comparison,
      orElse: () => cells[rng.nextInt(cells.length)],
    );
    final current = board.atCoord(comparison);
    if (current != null && current.kind == TileKind.comparison) {
      final mix = board.comparisonMix();
      final targets = comparisonTargets();
      final total = mix.values.fold<int>(0, (a, b) => a + b);
      double deficit(String g) => (targets[g] ?? 0) * total - (mix[g] ?? 0);
      final alternatives = operators.comparison
          .where((g) =>
              g != current.glyph && targets.containsKey(g) && deficit(g) > 0)
          .toList()
        ..sort((a, b) => deficit(b).compareTo(deficit(a)));

      for (final alternative in alternatives) {
        board.setCoord(comparison, current.copyWith(glyph: alternative));
        if (!_holds(board, match, minRunLength)) return;
      }
      board.setCoord(comparison, current);
    }

    // Only an equality-only tier can reach here, where there is nothing to
    // flip to. Spending the glyph always works.
    board.setCoord(comparison, nextDigit());
  }

  /// Whether [match]'s span still reads as a true statement.
  bool _holds(BoardModel board, BoardMatch match, int minRunLength) {
    final line = match.horizontal
        ? board.row(match.line)
        : board.column(match.line);
    for (final found in findAllEquations(line, minRunLength: minRunLength)) {
      if (found.start <= match.equation.start &&
          found.end >= match.equation.end) {
        return true;
      }
    }
    return false;
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
      _balanceComparisons(board, minRunLength);
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
      _balanceComparisons(board, minRunLength);
      if (hasAnyLegalMove(board, minRunLength: minRunLength)) return board;
    }

    throw BoardGenerationException(
      'no playable ${width}x$height board after ${maxAttempts * 2} attempts '
      '(minRunLength $minRunLength, minMoves $minMoves)',
    );
  }

  BoardModel _randomBoard(int width, int height, int cap) {
    final board = BoardModel(width: width, height: height, ids: ids);
    // Balancing the comparison glyphs as they are laid down, rather than
    // correcting the board afterwards. Correcting afterwards was measured at
    // 125ms a board: rewriting a comparison completes a true statement about
    // half the time, so every correction pass created fresh matches for the
    // repair loop to chase.
    final mix = <String, int>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Filling in reading order means only the left and upper neighbours
        // exist yet, which is enough: adjacency is symmetric, so a pair can only
        // be created by the second of the two cells.
        board.set(x, y, _drawFor(board, Coord(x, y), cap, mix));
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
