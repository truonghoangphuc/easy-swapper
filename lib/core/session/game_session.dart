/// The turn loop: swap, resolve, cascade, settle, judge. Pure Dart.
///
/// The session runs a whole resolution synchronously and hands back an ordered
/// list of [ResolveStep]s. The render layer then plays those back as
/// animations. Keeping the simulation ahead of the animation is what lets the
/// entire game loop be unit-tested without a Flame harness.
library;

import '../board/board_model.dart';
import '../board/move_solver.dart';
import '../board/tile.dart';
import '../board/tile_generator.dart';
import '../board/tile_queue.dart';
import '../levels/level_def.dart';
import '../rules/scoring.dart';

/// Where the session is in the turn loop.
enum SessionPhase {
  /// Waiting for the player.
  idle,

  /// A resolution is in flight; input is ignored.
  resolving,

  /// Objectives met.
  won,

  /// Out of moves, or hopelessly deadlocked.
  lost,
}

/// Why a swap was refused.
enum SwapRejection {
  /// The two cells are not orthogonally adjacent.
  notAdjacent,

  /// The swap completes no equation.
  noMatch,

  /// The session is mid-resolution or already over.
  wrongPhase,
}

/// One link in a cascade chain: what matched, what cleared, what moved.
class ResolveStep {
  const ResolveStep({
    required this.cascadeIndex,
    required this.matches,
    required this.cleared,
    required this.falls,
    required this.spawns,
    required this.baseScore,
    required this.multiplier,
    required this.feedback,
    this.detonations = const [],
  });

  /// 0 for the swap itself, 1 for the first cascade, and so on.
  final int cascadeIndex;

  final List<BoardMatch> matches;
  final Set<Coord> cleared;
  final List<TileFall> falls;
  final List<TileSpawn> spawns;

  /// Bomb positions that went off in this step, in detonation order. Empty for
  /// an ordinary equation step.
  final List<Coord> detonations;

  bool get isBlast => detonations.isNotEmpty;

  /// Sum of the raw equation scores, before the cascade multiplier.
  final int baseScore;

  final int multiplier;

  /// Celebration line, from the longest equation in this step.
  final String feedback;

  int get score => baseScore * multiplier;
}

/// The outcome of one player swap.
class SwapResult {
  const SwapResult.rejected(this.rejection)
      : accepted = false,
        steps = const [],
        boardReset = false;

  const SwapResult.accepted({required this.steps, required this.boardReset})
      : accepted = true,
        rejection = null;

  final bool accepted;
  final SwapRejection? rejection;

  /// Cascade chain, in play order. Empty only if the swap was rejected.
  final List<ResolveStep> steps;

  /// True if the board deadlocked afterwards, so the run was wiped and a fresh
  /// board dealt.
  final bool boardReset;

  int get totalScore => steps.fold(0, (sum, s) => sum + s.score);

  /// How deep the cascade went. 1 means no cascade.
  int get chainLength => steps.length;
}

/// One playthrough of one level.
class GameSession {
  GameSession({required this.level, required this.generator, BoardModel? board})
      : board = board ??
            generator.generateBoard(
              width: level.width,
              height: level.height,
              minRunLength: level.minRunLength,
            ) {
    // Primed here, not on the first refill: the preview is on screen from the
    // moment the board is, and an empty strip would read as a bug.
    replenishQueue();
  }

  final LevelDef level;
  final TileGenerator generator;
  final BoardModel board;

  /// The tile waiting to enter each column, shown to the player as the next
  /// drop. Primed on the first turn and topped up after every one.
  late final TileQueue queue = TileQueue(board.width);

  /// How many tiles the preview commits to in advance.
  ///
  /// This is a direct trade against playability, and the tool measures it: every
  /// committed tile is one the refill can no longer adapt to the cell it lands
  /// in. Anything past the queue falls through to the live fill, which can.
  /// Four, not a full row. The sweep in `tool/tune_weights.dart playout` is
  /// unambiguous: every committed tile is one the refill can no longer place
  /// intelligently, and at a full row of eight the board lost roughly half its
  /// playable life and most of its operator spacing. Four covers a typical
  /// turn's holes while leaving the tail adaptive.
  /// The preview holds one tile per column, so its length is the board width.

  /// How many operators the preview may hold at once, regardless of how long
  /// the preview is.
  ///
  /// Deliberately not a fraction of [previewLength]: tying the two together
  /// meant a longer preview also allowed a bigger restock burst, and four
  /// comparisons landing in one turn cannot all find a cell with room - they
  /// arrive as a clump. Two at a time gets the same supply in, spread over
  /// turns, into cells that can hold them apart.
  static const int maxOperatorBurst = 1;

  SessionPhase phase = SessionPhase.idle;

  int score = 0;
  int movesUsed = 0;
  int equationsCleared = 0;
  int longestChain = 0;
  int bombsDetonated = 0;

  /// The score the last wiped run reached.
  ///
  /// A deadlock zeroes [score], but the run still happened and is still worth
  /// submitting to a leaderboard - so the figure is kept here rather than lost.
  int lastRunScore = 0;

  /// How many times each glyph has appeared in a cleared equation.
  final Map<String, int> operatorUses = {};

  /// Cleared runs, bucketed by length, for the long-run objective.
  final Map<int, int> runsByLength = {};

  /// Cascade multipliers by depth. Capped so a lucky refill chain cannot be
  /// farmed into an unbounded score.
  static const int maxCascadeMultiplier = 5;

  /// How many bombs may sit on the board at once.
  ///
  /// A bomb never tokenizes, so each one is a permanent hole in the equations
  /// the player can still form. Three is enough to feel available without
  /// starving the board of matches.
  static const int maxBombsOnBoard = 3;

  int get movesRemaining => level.isEndless ? -1 : level.moves - movesUsed;

  bool get isOver => phase == SessionPhase.won || phase == SessionPhase.lost;

  int get stars => level.starsFor(score);

  /// True once every objective on the level is satisfied.
  ///
  /// A level with no objectives is endless, not instantly won - note that
  /// `[].every(...)` is vacuously true, which is exactly the trap here.
  bool get objectivesMet =>
      level.objectives.isNotEmpty && level.objectives.every(_isMet);

  bool _isMet(Objective objective) => switch (objective) {
        ReachScore(:final target) => score >= target,
        ClearEquations(:final count) => equationsCleared >= count,
        UseOperator(:final glyph, :final count) =>
          (operatorUses[glyph] ?? 0) >= count,
        ClearLongEquations(:final count, :final minLength) =>
          runsByLength.entries
              .where((e) => e.key >= minLength)
              .fold<int>(0, (sum, e) => sum + e.value) >=
              count,
      };

  /// Progress on [objective] as a 0..1 fraction, for the HUD.
  double progressOn(Objective objective) => switch (objective) {
        ReachScore(:final target) => (score / target).clamp(0.0, 1.0),
        ClearEquations(:final count) =>
          (equationsCleared / count).clamp(0.0, 1.0),
        UseOperator(:final glyph, :final count) =>
          ((operatorUses[glyph] ?? 0) / count).clamp(0.0, 1.0),
        ClearLongEquations(:final count, :final minLength) => (runsByLength
                    .entries
                    .where((e) => e.key >= minLength)
                    .fold<int>(0, (sum, e) => sum + e.value) /
                count)
            .clamp(0.0, 1.0),
      };

  /// Attempts the player's swap.
  ///
  /// On success the board is left fully settled - cascaded, refilled, and
  /// reshuffled if it deadlocked - and the returned steps describe how it got
  /// there. On rejection the board is untouched and no move is consumed.
  SwapResult trySwap(Coord a, Coord b) {
    if (phase != SessionPhase.idle) {
      return const SwapResult.rejected(SwapRejection.wrongPhase);
    }
    if (!a.isAdjacentTo(b)) {
      return const SwapResult.rejected(SwapRejection.notAdjacent);
    }

    board.swap(a, b);

    // A bomb goes off wherever it lands, so a swap involving one is legal even
    // though it completes nothing.
    final bombs = [
      for (final cell in [a, b])
        if (board.atCoord(cell)?.isBomb ?? false) cell,
    ];

    // Only the swapped rows and columns can have changed, because the board was
    // settled and match-free before this call.
    var matches =
        board.findMatchesAffectedBy(a, b, minRunLength: level.minRunLength);
    if (matches.isEmpty && bombs.isEmpty) {
      board.swap(a, b);
      return const SwapResult.rejected(SwapRejection.noMatch);
    }

    phase = SessionPhase.resolving;
    movesUsed++;

    final steps = <ResolveStep>[];
    var cascadeIndex = 0;

    if (bombs.isNotEmpty) {
      // The blast resolves first and on its own. It clears cells any equation
      // in the swapped lines would have used, so those are rescanned afterwards
      // as an ordinary cascade rather than being scored twice.
      steps.add(_detonate(bombs, cascadeIndex));
      matches = board.findMatches(minRunLength: level.minRunLength);
      cascadeIndex++;
    }

    while (matches.isNotEmpty) {
      steps.add(_resolve(matches, cascadeIndex));
      // A refill can complete an equation anywhere, so the cascade rescan has
      // to cover the whole board rather than just the swapped lines.
      matches = board.findMatches(minRunLength: level.minRunLength);
      cascadeIndex++;
    }

    if (steps.length > longestChain) longestChain = steps.length;

    final wasReset = _settle();
    _judge(wasReset);
    return SwapResult.accepted(steps: steps, boardReset: wasReset);
  }

  ResolveStep _resolve(List<BoardMatch> matches, int cascadeIndex) {
    final cleared = board.cellsToClear(matches);

    var baseScore = 0;
    var feedback = '';
    var longest = 0;
    for (final match in matches) {
      baseScore += match.score;
      equationsCleared++;

      final length = match.equation.length;
      runsByLength.update(length, (v) => v + 1, ifAbsent: () => 1);
      for (final glyph in match.equation.cells) {
        operatorUses.update(glyph, (v) => v + 1, ifAbsent: () => 1);
      }
      if (length > longest) {
        longest = length;
        feedback = match.equation.feedback;
      }
    }

    final multiplier =
        (cascadeIndex + 1).clamp(1, maxCascadeMultiplier);
    score += baseScore * multiplier;

    board.clear(cleared);
    final falls = board.compact();
    final spawns = _refill();

    return ResolveStep(
      cascadeIndex: cascadeIndex,
      matches: matches,
      cleared: cleared,
      falls: falls,
      spawns: spawns,
      baseScore: baseScore,
      multiplier: multiplier,
      feedback: feedback,
    );
  }

  /// Sets off every bomb in [origins], plus any bomb caught in the blast.
  ///
  /// Blast cells are not equations, so they do not advance the equation-count
  /// or operator objectives - a bomb is a shortcut, not a solve.
  ResolveStep _detonate(List<Coord> origins, int cascadeIndex) {
    final detonated = <Coord>[];
    final seen = <Coord>{};
    final cells = <Coord>{};

    final queue = [...origins];
    while (queue.isNotEmpty) {
      final origin = queue.removeAt(0);
      if (!seen.add(origin)) continue;
      detonated.add(origin);

      for (final cell in board.blastCells(origin)) {
        cells.add(cell);
        // Chain into any other bomb the blast touches.
        if ((board.atCoord(cell)?.isBomb ?? false) && !seen.contains(cell)) {
          queue.add(cell);
        }
      }
    }

    final scored = scoreBlast(cells.length);
    bombsDetonated += detonated.length;
    score += scored.score;

    board.clear(cells);
    final falls = board.compact();
    final spawns = _refill();

    return ResolveStep(
      cascadeIndex: cascadeIndex,
      matches: const [],
      cleared: cells,
      falls: falls,
      spawns: spawns,
      baseScore: scored.score,
      multiplier: 1,
      feedback: scored.feedback,
      detonations: detonated,
    );
  }

  /// Refills the board, holding the same composition rules generation does:
  /// bombs capped, operators under budget, and as few side by side as possible.
  ///
  /// Each column's first hole receives the tile the preview promised it. That
  /// commitment is made a turn early, so the refill cannot vet a queued tile
  /// against the cell it lands in - only the leftover holes get that treatment.
  /// Which columns are handed operators in the first place is chosen in
  /// [replenishQueue], and that is where the spacing is actually defended.
  List<TileSpawn> _refill() {
    final cap = generator.operatorCapFor(board.width, board.height);

    // The cell each column fills *first*: the bottom-most hole, not the
    // top-most. Tiles fall in, so the next one to drop leads and comes to rest
    // deepest while the rest stack on it.
    final assignment = <Coord, Tile>{};
    for (var x = 0; x < board.width; x++) {
      final tile = queue.peek(x);
      if (tile == null) continue;
      for (var y = board.height - 1; y >= 0; y--) {
        if (board.at(x, y) != null) continue;
        assignment[Coord(x, y)] = tile;
        queue.take(x);
        break;
      }
    }

    // Everything else falls to the planner, which can see the cell it fills.
    final unplanned = board
        .emptyCells()
        .where((c) => !assignment.containsKey(c))
        .toList()
      ..sort(
        (a, b) => board
            .operatorNeighbourCount(a)
            .compareTo(board.operatorNeighbourCount(b)),
      );

    // Everything the assignment will place counts from the start. The fill
    // interleaves assigned cells with live ones, so counting a queued bomb only
    // when its cell comes up let a live cell slip one in first and put four on
    // a board capped at three.
    var bombs = board.bombCells().length +
        assignment.values.where((t) => t.isBomb).length;
    var operators =
        board.operatorCount() + assignment.values.where(isOperator).length;

    final needComparison =
        generator.comparisonFloorFor(board.width, board.height) -
            board.comparisonCount() -
            assignment.values
                .where((t) => t.kind == TileKind.comparison)
                .length;
    final needOperator =
        generator.operatorFloorFor(board.width, board.height) - operators;
    final spare = (cap - operators).clamp(0, cap);

    final comparisonSlots = _planSlots(
      unplanned,
      needed: needComparison.clamp(0, spare),
      skipCorners: true,
      relaxIfShort: true,
    );
    final operatorRoom = (spare - comparisonSlots.length).clamp(0, spare);
    final operatorSlots = _planSlots(
      unplanned,
      needed: (needOperator - comparisonSlots.length).clamp(0, operatorRoom),
      skipCorners: false,
      taken: comparisonSlots,
      relaxIfShort: false,
    );

    final reserved = {
      ...comparisonSlots,
      ...operatorSlots,
      for (final entry in assignment.entries)
        if (isOperator(entry.value)) entry.key,
    };

    final spawns = board.refill((at) {
      final promised = assignment[at];
      if (promised != null) return promised;

      if (comparisonSlots.contains(at)) {
        operators++;
        return generator.nextComparison();
      }
      if (operatorSlots.contains(at)) {
        operators++;
        return generator.nextOperator();
      }

      // A reserved slot is an operator that has not landed yet, so it counts as
      // a neighbour. Without this the fill order decides whether a pair forms.
      final clear = board.operatorNeighbourCount(at) == 0 &&
          !reserved.any(at.isAdjacentTo);

      final tile = generator.nextRefillTile(
        allowBomb: bombs + queue.bombCount() < maxBombsOnBoard,
        allowOperator: operators < cap && clear,
      );
      if (tile.isBomb) bombs++;
      if (isOperator(tile)) operators++;
      return tile;
    });

    replenishQueue();
    return spawns;
  }

  /// Tops the preview back up, one tile per empty column.
  ///
  /// The interesting decision is *which* columns get the operators. A queued
  /// tile is committed to its column before its row is known, so it cannot be
  /// checked against its neighbours the way a live fill can; the compensation is
  /// to hand operators to the columns whose neighbourhoods hold fewest already.
  /// Drawing blindly per column instead left half the board's operators clumped
  /// against each other.
  ///
  /// Budgets use opposite accounting on purpose. The cap counts the board *plus*
  /// the queue, so committed tiles can never overshoot it - between queueing and
  /// dropping a board only ever loses operators, to matches. The floors count
  /// the board alone: a queued operator has not landed yet, and treating it as
  /// if it had left the board starved while the queue held the difference.
  void replenishQueue() {
    final columns = queue.emptyColumns();
    if (columns.isEmpty) return;

    final cap = generator.operatorCapFor(board.width, board.height);
    final comparisonFloor =
        generator.comparisonFloorFor(board.width, board.height);
    final operatorFloor =
        generator.operatorFloorFor(board.width, board.height);

    var operators = board.operatorCount() + queue.operatorCount();
    var comparisons = board.comparisonCount();
    var boardOperators = board.operatorCount();

    // How many of these slots should carry an operator, and how many of those
    // must be comparisons.
    var wantComparison = 0;
    var wantOperator = 0;
    for (var i = 0; i < columns.length; i++) {
      if (operators + wantOperator >= cap) break;
      if (wantOperator >= maxOperatorBurst) break;
      if (comparisons + wantComparison < comparisonFloor) {
        wantComparison++;
        wantOperator++;
        continue;
      }
      if (boardOperators + wantOperator < operatorFloor) {
        wantOperator++;
        continue;
      }
      break;
    }

    // Least crowded columns first, so the operators go where they have room.
    final ranked = [...columns]
      ..sort((a, b) => board.columnCrowding(a).compareTo(board.columnCrowding(b)));

    for (var i = 0; i < ranked.length; i++) {
      final column = ranked[i];
      if (i < wantComparison) {
        queue.fill(column, generator.nextComparison());
        comparisons++;
        operators++;
        boardOperators++;
        continue;
      }
      if (i < wantOperator) {
        final tile = generator.nextOperator();
        if (tile.kind == TileKind.comparison) comparisons++;
        queue.fill(column, tile);
        operators++;
        boardOperators++;
        continue;
      }

      if (board.bombCells().length + queue.bombCount() < maxBombsOnBoard &&
          generator.rng.nextDouble() < generator.bombChance) {
        queue.fill(column, Tile.bomb(generator.ids.nextId()));
        continue;
      }
      queue.fill(column, generator.nextDigit());
    }
  }

  /// Picks [needed] refill slots to hold an operator, preferring cells with no
  /// operator beside them.
  ///
  /// The first pass takes only cells clean of operators, in the board and in the
  /// plan so far. When [relaxIfShort] is set and supply still falls short, a
  /// second pass drops that requirement - a board that runs out of comparisons
  /// is dead, and one with a couple of operator pairs is merely untidy. Callers
  /// that can live without the tile leave it off.
  Set<Coord> _planSlots(
    List<Coord> empties, {
    required int needed,
    required bool skipCorners,
    required bool relaxIfShort,
    Set<Coord> taken = const {},
  }) {
    final planned = <Coord>{};
    if (needed <= 0) return planned;

    bool isCorner(Coord c) =>
        (c.x == 0 || c.x == board.width - 1) &&
        (c.y == 0 || c.y == board.height - 1);

    final ranked = [...empties]..sort(
        (a, b) => board
            .operatorNeighbourCount(a)
            .compareTo(board.operatorNeighbourCount(b)),
      );

    for (final clean in relaxIfShort ? [true, false] : [true]) {
      for (final cell in ranked) {
        if (planned.length >= needed) return planned;
        if (taken.contains(cell) || planned.contains(cell)) continue;
        // A comparison in a corner has no cell on one side either way, so it can
        // never anchor a run.
        if (skipCorners && isCorner(cell)) continue;
        if (clean &&
            (board.hasOperatorNeighbour(cell) ||
                planned.any(cell.isAdjacentTo) ||
                taken.any(cell.isAdjacentTo))) {
          continue;
        }
        planned.add(cell);
      }
    }
    return planned;
  }

  /// Deals a whole new board and wipes the run if nothing can be swapped.
  ///
  /// Returns true if that happened. This replaces the usual match-three
  /// reshuffle: a shuffle keeps the score, and the player has not earned a free
  /// recovery from a board they played into a corner.
  bool _settle() {
    if (hasAnyLegalMove(board, minRunLength: level.minRunLength)) return false;
    resetAfterDeadlock();
    return true;
  }

  /// Wipes the score and progress and deals a fresh board.
  ///
  /// The board is rebuilt in place so the render layer keeps the same
  /// [BoardModel] instance and can just resync from it.
  void resetAfterDeadlock() {
    lastRunScore = score;
    score = 0;
    equationsCleared = 0;
    longestChain = 0;
    bombsDetonated = 0;
    operatorUses.clear();
    runsByLength.clear();
    if (!level.isEndless) movesUsed = 0;

    final fresh = generator.generateBoard(
      width: board.width,
      height: board.height,
      minRunLength: level.minRunLength,
    );
    for (var y = 0; y < board.height; y++) {
      for (var x = 0; x < board.width; x++) {
        board.set(x, y, fresh.at(x, y));
      }
    }

    queue.clear();
    replenishQueue();
  }

  void _judge(bool wasReset) {
    // A reset zeroes the score, so any objective met on the way is gone with it.
    if (!wasReset && objectivesMet) {
      phase = SessionPhase.won;
      return;
    }
    if (!wasReset && !level.isEndless && movesRemaining <= 0) {
      phase = SessionPhase.lost;
      return;
    }
    phase = SessionPhase.idle;
  }

  /// The highest-scoring swap available, for the idle hint.
  Move? hint() => findBestMove(board, minRunLength: level.minRunLength);
}
