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
import '../levels/difficulty_ramp.dart';
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

  /// The board is animating or the run is over.
  wrongPhase,

  /// In the tutorial, only the correct hinted move is allowed.
  tutorialLock,

  /// One of the bricks is still encased and cannot be picked up.
  lockedTile,
}

/// One electric discharge: where it fired from and what it took.
class Zap {
  const Zap({required this.origin, required this.glyph, required this.targets});

  /// The cell the electric was sitting in when it went off.
  final Coord origin;

  /// The glyph it swept for, or null when it took every digit - which is what
  /// two electrics swapped together do.
  final String? glyph;

  /// Every cell it reached, encased bricks included.
  final Set<Coord> targets;
}

/// One link in a cascade chain: what matched, what cleared, what moved.
class ResolveStep {
  const ResolveStep({
    required this.cascadeIndex,
    required this.matches,
    required this.cleared,
    this.cracked = const {},
    required this.falls,
    required this.spawns,
    required this.baseScore,
    required this.multiplier,
    required this.feedback,
    this.detonations = const [],
    this.zaps = const [],
  });

  /// 0 for the swap itself, 1 for the first cascade, and so on.
  final int cascadeIndex;

  /// Equations that resolved in this step.
  final List<BoardMatch> matches;

  /// Cells that were removed from the board.
  final Set<Coord> cleared;

  /// Encased bricks that took a hit, mapped to the brick each cell now holds.
  /// An `armor` of zero means it came free and is ordinary from here on.
  ///
  /// The *tile*, not just the depth: by the time the render layer replays this
  /// step the model has compacted and refilled past it, so the coordinate no
  /// longer identifies the brick that was hit. The tile's id does.
  final Map<Coord, Tile> cracked;

  /// The post-clear compaction.
  final List<TileFall> falls;
  final List<TileSpawn> spawns;

  /// Bomb positions that went off in this step, in detonation order. Empty for
  /// an ordinary equation step.
  final List<Coord> detonations;

  /// Electric discharges in this step. Empty for anything else.
  final List<Zap> zaps;

  bool get isBlast => detonations.isNotEmpty;

  bool get isZap => zaps.isNotEmpty;

  /// True for any power-up step, as opposed to a resolved equation.
  bool get isDischarge => isBlast || isZap;

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

/// What a refill or a queue slot is currently allowed to produce.
///
/// Every non-tokenizing brick - bomb, electric, encased - is a hole in the
/// equations the player can still build, so they share one ceiling as well as
/// having their own. Per-type caps alone let the total drift upward until the
/// board quietly stops offering moves, which on this game costs the run's
/// whole score.
class _ObstacleBudget {
  _ObstacleBudget({
    required this.stage,
    required this.bombs,
    required this.electrics,
    required this.encased,
    required this.diamonds,
  });

  final DifficultyStage stage;
  int bombs;
  int electrics;
  int encased;
  int diamonds;

  int get total => bombs + electrics + encased;

  bool get _hasRoom => total < stage.maxObstacles;

  bool get canBomb => _hasRoom && bombs < GameSession.maxBombsOnBoard;

  bool get canElectric =>
      _hasRoom &&
      stage.electricChance > 0 &&
      electrics < GameSession.maxElectricsOnBoard;

  /// Deepest casing this slot may carry: none, stone, or diamond.
  int get casingAllowance {
    if (!_hasRoom || encased >= stage.maxEncased) return Armor.none;
    return diamonds < stage.maxDiamonds ? Armor.diamond : Armor.stone;
  }

  /// Books [tile] against the budget, whatever it turned out to be.
  void record(Tile tile) {
    if (tile.isBomb) bombs++;
    if (tile.isElectric) electrics++;
    if (tile.isEncased) {
      encased++;
      if (tile.armor >= Armor.diamond) diamonds++;
    }
  }
}

/// One playthrough of one level.
class GameSession {
  GameSession({required this.level, required this.generator, BoardModel? board})
      : board = board ?? _openingBoard(level, generator) {
    _applyRamp();
    // Primed here, not on the first refill: the preview is on screen from the
    // moment the board is, and an empty strip would read as a bug.
    replenishQueue();
  }

  /// Deals the first board, with the ramp already applied.
  ///
  /// The order matters and it is easy to get wrong: the board used to be built
  /// in the initialiser list, which runs *before* the constructor body, so the
  /// opening board of every endless run was drawn from the default weights
  /// rather than from stage zero of its own ramp. Measured, that put `=` at
  /// 88% of the comparison glyphs on a board whose stage asks for 50%.
  static BoardModel _openingBoard(LevelDef level, TileGenerator generator) {
    generator.applyStage(level.ramp.stages.first);
    return generator.generateBoard(
      width: level.width,
      height: level.height,
      minRunLength: level.minRunLength,
    );
  }

  final LevelDef level;
  final TileGenerator generator;
  final BoardModel board;

  /// The tile waiting to enter each column, shown to the player as the next
  /// drop. Primed on the first turn and topped up after every one.
  late final TileQueue queue = TileQueue(board.width);

  /// Which rung of [LevelDef.ramp] this run is on.
  ///
  /// Derived purely from [score], so it needs no persisting and a deadlock
  /// wipe rolls it back to the start for free.
  int stageIndex = 0;

  DifficultyStage get stage => level.ramp.stages[stageIndex];

  /// How many operators the preview may hold at once, regardless of how long
  /// the preview is.
  ///
  /// Deliberately not a fraction of the preview length: tying the two together
  /// meant a longer preview also allowed a bigger restock burst, and four
  /// comparisons landing in one turn cannot all find a cell with room - they
  /// arrive as a clump. One at a time gets the same supply in, spread over
  /// turns, into cells that can hold them apart.
  static const int maxOperatorBurst = 1;

  SessionPhase phase = SessionPhase.idle;

  int score = 0;
  int movesUsed = 0;
  int equationsCleared = 0;
  int longestChain = 0;
  int bombsDetonated = 0;

  /// How many electrics the player has set off.
  int electricsFired = 0;

  /// How many casings have been broken through, and how many bricks that has
  /// actually set free. A diamond costs two of the first for one of the second.
  int casingsCracked = 0;
  int bricksFreed = 0;

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

  /// How many electrics may sit on the board at once.
  ///
  /// Lower than the bomb cap. An electric can take a dozen bricks at once, so
  /// two waiting is already a large reserve.
  static const int maxElectricsOnBoard = 2;

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

  /// True if this is the very first move of Level 1.
  bool get isTutorialActive => level.id == 1 && score == 0;

  /// Moves the generator onto whichever stage the current score sits in.
  ///
  /// Called after every score change and after a wipe. Cheap and idempotent -
  /// the generator only rebuilds its draw table when the stage really changed.
  void _applyRamp() {
    final next = level.ramp.indexFor(score);
    stageIndex = next;
    generator.applyStage(level.ramp.stages[next]);
  }

  /// Attempts a swap and returns the resolution trace.
  ///
  /// If the swap is valid it is applied, the cascades are resolved - and the board
  /// reshuffled if it deadlocked - and the returned steps describe how it got
  /// there. On rejection the board is untouched and no move is consumed.
  SwapResult trySwap(Coord a, Coord b) {
    if (phase != SessionPhase.idle) {
      return const SwapResult.rejected(SwapRejection.wrongPhase);
    }
    if (!a.isAdjacentTo(b)) {
      return const SwapResult.rejected(SwapRejection.notAdjacent);
    }

    // An encased brick is pinned until its casing breaks - unless a power-up
    // is doing the breaking. `move_solver` shares this predicate, so the hint
    // and the deadlock check can never disagree with what is actually allowed.
    if (!canSwapPair(board.atCoord(a), board.atCoord(b))) {
      return const SwapResult.rejected(SwapRejection.lockedTile);
    }

    if (isTutorialActive) {
      final best = hint();
      if (best != null) {
        if (!((a == best.a && b == best.b) || (a == best.b && b == best.a))) {
          return const SwapResult.rejected(SwapRejection.tutorialLock);
        }
      }
    }

    board.swap(a, b);

    // A power-up fires wherever it lands, so a swap involving one is legal even
    // though it completes nothing.
    final bombs = [
      for (final cell in [a, b])
        if (board.atCoord(cell)?.isBomb ?? false) cell,
    ];
    final electrics = [
      for (final cell in [a, b])
        if (board.atCoord(cell)?.isElectric ?? false) cell,
    ];

    // Only the swapped rows and columns can have changed, because the board was
    // settled and match-free before this call.
    var matches =
        board.findMatchesAffectedBy(a, b, minRunLength: level.minRunLength);
    if (matches.isEmpty && bombs.isEmpty && electrics.isEmpty) {
      board.swap(a, b);
      return const SwapResult.rejected(SwapRejection.noMatch);
    }

    phase = SessionPhase.resolving;
    movesUsed++;

    final steps = <ResolveStep>[];
    var cascadeIndex = 0;

    if (bombs.isNotEmpty || electrics.isNotEmpty) {
      // The discharge resolves first and on its own. It clears cells any
      // equation in the swapped lines would have used, so those are rescanned
      // afterwards as an ordinary cascade rather than being scored twice.
      steps.add(
        _discharge(
          bombs: bombs,
          electrics: electrics,
          a: a,
          b: b,
          cascadeIndex: cascadeIndex,
        ),
      );
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

  /// What one set of struck cells does to the board.
  ///
  /// Splits [hit] into bricks that clear and encased bricks that only take
  /// damage, then adds the encased neighbours of everything that cleared -
  /// which is what makes a resolved equation an *impact* on the stone sitting
  /// next to it.
  ///
  /// A brick with three cleared neighbours still takes one hit, not three: the
  /// working set is a [Set], and that is doing real work.
  ({Set<Coord> cleared, Map<Coord, Tile> cracked, int bonus}) _applyImpact(
    Set<Coord> hit,
  ) {
    final cleared = <Coord>{};
    final struck = <Coord>{};
    for (final cell in hit) {
      final tile = board.atCoord(cell);
      if (tile == null) continue;
      (tile.isEncased ? struck : cleared).add(cell);
    }
    struck.addAll(board.encasedNeighboursOf(cleared));

    final cracked = board.damage(struck);
    var bonus = 0;
    for (final tile in cracked.values) {
      bonus += scoreCrack(tile.armor).score;
      casingsCracked++;
      if (tile.armor == Armor.none) bricksFreed++;
    }

    board.clear(cleared);
    return (cleared: cleared, cracked: cracked, bonus: bonus);
  }

  ResolveStep _resolve(List<BoardMatch> matches, int cascadeIndex) {
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

    final impact = _applyImpact(board.cellsToClear(matches));

    final multiplier = (cascadeIndex + 1).clamp(1, maxCascadeMultiplier);
    // The casing bonus is flat, not multiplied: a cascade earns its multiplier
    // by chaining equations, and cracking stone on the way is incidental.
    score += baseScore * multiplier + impact.bonus;
    _applyRamp();

    if (feedback.isEmpty && impact.cracked.isNotEmpty) {
      // The shallowest casing left is the best news in the step: if anything
      // came free, that is what the player should be told about.
      feedback = scoreCrack(
        impact.cracked.values.map((t) => t.armor).reduce((a, b) => a < b ? a : b),
      ).feedback;
    }

    final falls = board.compact();
    final spawns = _refill();

    return ResolveStep(
      cascadeIndex: cascadeIndex,
      matches: matches,
      cleared: impact.cleared,
      cracked: impact.cracked,
      falls: falls,
      spawns: spawns,
      baseScore: baseScore,
      multiplier: multiplier,
      feedback: feedback,
    );
  }

  /// Fires every power-up caught up in one swap, as a single event.
  ///
  /// Bombs and electrics resolve together rather than in sequence because a
  /// bomb that is still on the board after an electric has compacted and
  /// refilled around it is no longer where its coordinate says it is. Taking
  /// the union of what each would destroy and clearing once sidesteps that
  /// entirely, and it is what makes a bomb-into-electric swap do both things.
  ///
  /// Neither a blast nor a discharge is an equation, so neither advances the
  /// equation-count or operator objectives - a power-up is a shortcut, not a
  /// solve.
  ResolveStep _discharge({
    required List<Coord> bombs,
    required List<Coord> electrics,
    required Coord a,
    required Coord b,
    required int cascadeIndex,
  }) {
    final detonated = <Coord>[];
    final blast = <Coord>{};
    final seen = <Coord>{};

    // Electrics that will fire: the ones swapped, plus any a blast reaches.
    // Bombs have always chained into bombs, but an electric swept by a blast
    // used to be cleared in silence - which destroyed the rarest brick on the
    // board for nothing. A blast now sets off everything it touches.
    final firing = <Coord>[...electrics];

    final pending = [...bombs];
    while (pending.isNotEmpty) {
      final origin = pending.removeAt(0);
      if (!seen.add(origin)) continue;
      detonated.add(origin);

      for (final cell in board.blastCells(origin)) {
        blast.add(cell);
        final tile = board.atCoord(cell);
        if (tile == null) continue;
        if (tile.isBomb && !seen.contains(cell)) {
          pending.add(cell);
        } else if (tile.isElectric && !firing.contains(cell)) {
          firing.add(cell);
        }
      }
    }

    final zaps = <Zap>[];
    final zapped = <Coord>{};

    // Two electrics swapped into each other fire as one event - the classic
    // double, which takes every digit - rather than as two sweeps.
    final pairSwapped = electrics.length == 2;

    for (final origin in firing) {
      if (pairSwapped && origin == electrics.last) continue;

      // A swapped electric targets the brick it displaced. One set off by a
      // blast has no partner, so it falls back to the commonest glyph, the
      // same way a swap into another power-up does.
      final Coord? partnerCell = pairSwapped
          ? null
          : origin == a
              ? b
              : origin == b
                  ? a
                  : null;
      final sweep = electricSweep(
        board,
        partner: partnerCell == null ? null : board.atCoord(partnerCell),
        bothElectric: pairSwapped,
      );
      zapped.addAll(sweep.cells);
      zaps.add(Zap(origin: origin, glyph: sweep.glyph, targets: sweep.cells));
    }

    // Every electric involved is spent, including the second of a pair.
    zapped.addAll(firing);
    electricsFired += firing.length;

    bombsDetonated += detonated.length;

    final impact = _applyImpact({...blast, ...zapped});

    // Each power-up is paid for what it actually destroyed, and each cell is
    // paid once.
    //
    // Counting the raw sweeps instead overpaid twice over: an encased brick
    // caught in a blast survives it, yet was billed at the full per-cell rate
    // *and* again as a casing broken - a nine-cell cross over five stone
    // bricks scored 75 for destroying four of them. A cell in both a cross and
    // a discharge was charged to both as well. The casing bonus in
    // [_applyImpact] is the only thing a surviving brick earns.
    final blastCells = blast.intersection(impact.cleared);
    final zapCells = zapped.intersection(impact.cleared).difference(blastCells);

    final scoredBlast = detonated.isEmpty ? null : scoreBlast(blastCells.length);
    final scoredZap = zaps.isEmpty ? null : scoreElectric(zapCells.length);

    final base =
        (scoredBlast?.score ?? 0) + (scoredZap?.score ?? 0) + impact.bonus;
    score += base;
    _applyRamp();

    // Whichever half was the bigger event gets to name it.
    final feedback = (scoredZap?.score ?? 0) >= (scoredBlast?.score ?? 0)
        ? (scoredZap?.feedback ?? '')
        : (scoredBlast?.feedback ?? '');

    final falls = board.compact();
    final spawns = _refill();

    return ResolveStep(
      cascadeIndex: cascadeIndex,
      matches: const [],
      cleared: impact.cleared,
      cracked: impact.cracked,
      falls: falls,
      spawns: spawns,
      baseScore: base,
      multiplier: 1,
      feedback: feedback,
      detonations: detonated,
      zaps: zaps,
    );
  }

  /// Counts what is already committed, on the board and in the preview.
  _ObstacleBudget _budget({Iterable<Tile> pending = const []}) {
    final budget = _ObstacleBudget(
      stage: stage,
      bombs: board.bombCells().length + queue.bombCount(),
      electrics: board.electricCells().length + queue.electricCount(),
      encased: board.encasedCells().length + queue.encasedCount(),
      diamonds: _diamondsOnBoard() + queue.diamondCount(),
    );
    for (final tile in pending) {
      budget.record(tile);
    }
    return budget;
  }

  int _diamondsOnBoard() {
    var count = 0;
    for (final cell in board.encasedCells()) {
      if ((board.atCoord(cell)?.armor ?? 0) >= Armor.diamond) count++;
    }
    return count;
  }

  /// Refills the board, holding the same composition rules generation does:
  /// obstacles capped, operators under budget, and as few side by side as
  /// possible.
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
    // interleaves assigned cells with live ones, so counting a queued obstacle
    // only when its cell comes up let a live cell slip one in first and put
    // four on a board capped at three.
    final budget = _budget(pending: assignment.values);

    // Two operator counts, on purpose. The ceiling sees encased operators -
    // they crowd the board and they will come free one day. The floors do not:
    // an operator the player cannot reach is no supply at all.
    var capOperators =
        board.operatorCount() + assignment.values.where(isOperator).length;
    final usableOperators = board.usableOperatorCount() +
        assignment.values.where(isUsableOperator).length;

    final needComparison =
        generator.comparisonFloorFor(board.width, board.height) -
            board.comparisonCount() -
            assignment.values
                .where((t) => t.kind == TileKind.comparison && !t.isEncased)
                .length;
    final needOperator =
        generator.operatorFloorFor(board.width, board.height) - usableOperators;
    final spare = (cap - capOperators).clamp(0, cap);

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

    // The comparison mix the board will be left holding, updated as slots are
    // committed. Top-ups are drawn against this rather than blind, because
    // matches consume inequalities much faster than equality and a blind draw
    // leaves the board silting up with `=`.
    final mix = board.comparisonMix();
    for (final tile in assignment.values) {
      if (tile.kind == TileKind.comparison && !tile.isEncased) {
        mix.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    final reserved = {
      ...comparisonSlots,
      ...operatorSlots,
      for (final entry in assignment.entries)
        if (isOperator(entry.value)) entry.key,
    };

    final spawns = board.refill((at) {
      final promised = assignment[at];
      if (promised != null) return promised;

      // A floor top-up is never encased. These exist precisely to keep the
      // board playable, and sealing one under stone defeats the whole point of
      // planting it.
      if (comparisonSlots.contains(at)) {
        capOperators++;
        final tile = generator.nextComparisonFor(mix);
        mix.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
        return tile;
      }
      if (operatorSlots.contains(at)) {
        capOperators++;
        final tile = generator.nextOperator();
        if (tile.kind == TileKind.comparison) {
          mix.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
        }
        return tile;
      }

      // A reserved slot is an operator that has not landed yet, so it counts as
      // a neighbour. Without this the fill order decides whether a pair forms.
      final clear = board.operatorNeighbourCount(at) == 0 &&
          !reserved.any(at.isAdjacentTo);

      final tile = generator.nextRefillTile(
        allowBomb: budget.canBomb,
        allowElectric: budget.canElectric,
        allowOperator: capOperators < cap && clear,
        maxCasing: budget.casingAllowance,
      );
      budget.record(tile);
      if (isOperator(tile)) capOperators++;
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
  /// the board alone, and only the operators on it the player can actually use.
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
    var usableOperators = board.usableOperatorCount();

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
      if (usableOperators + wantOperator < operatorFloor) {
        wantOperator++;
        continue;
      }
      break;
    }

    // Least crowded columns first, so the operators go where they have room.
    final ranked = [...columns]
      ..sort((a, b) => board.columnCrowding(a).compareTo(board.columnCrowding(b)));

    final budget = _budget();
    final mix = board.comparisonMix();
    queue.comparisonMix().forEach((glyph, count) {
      mix.update(glyph, (v) => v + count, ifAbsent: () => count);
    });

    for (var i = 0; i < ranked.length; i++) {
      final column = ranked[i];
      if (i < wantComparison) {
        final tile = generator.nextComparisonFor(mix);
        mix.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
        queue.fill(column, tile);
        comparisons++;
        operators++;
        usableOperators++;
        continue;
      }
      if (i < wantOperator) {
        final tile = generator.nextOperator();
        if (tile.kind == TileKind.comparison) {
          comparisons++;
          mix.update(tile.glyph, (v) => v + 1, ifAbsent: () => 1);
        }
        queue.fill(column, tile);
        operators++;
        usableOperators++;
        continue;
      }

      // The digit slots are where obstacles get in. A queued one is visible in
      // the preview a turn before it lands, which is the warning the player
      // needs to plan around it.
      final tile = generator.nextRefillTile(
        allowBomb: budget.canBomb,
        allowElectric: budget.canElectric,
        allowOperator: false,
        // Wildcards stay a live-fill draw. A queued one costs a digit slot,
        // and digits are what an equation is mostly made of - measured, that
        // alone pushed operator adjacency from 51.5% to 52.9%. Obstacles are
        // worth queueing because the preview warns the player about them a
        // turn early; a wildcard needs no warning.
        allowWildcard: false,
        maxCasing: budget.casingAllowance,
      );
      budget.record(tile);
      queue.fill(column, tile);
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
    electricsFired = 0;
    casingsCracked = 0;
    bricksFreed = 0;
    operatorUses.clear();
    runsByLength.clear();
    if (!level.isEndless) movesUsed = 0;

    // Back to the opening stage, because the ramp reads the score and the
    // score is gone. Has to happen before the board is dealt: the fresh board
    // is drawn from whichever distribution is current.
    _applyRamp();
    _dealFreshBoard();
  }

  /// Reshuffles the board with a fresh layout while **keeping** the current
  /// score. Called as the reward for watching a rewarded ad on deadlock.
  ///
  /// Structurally identical to [resetAfterDeadlock] but does not touch score,
  /// chain stats, or [lastRunScore] - and so does not touch the ramp either.
  void shuffleBoard() => _dealFreshBoard();

  void _dealFreshBoard() {
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

  Map<String, dynamic> toJson() => {
        'levelId': level.id,
        'phase': phase.name,
        'score': score,
        'movesUsed': movesUsed,
        'equationsCleared': equationsCleared,
        'longestChain': longestChain,
        'bombsDetonated': bombsDetonated,
        'electricsFired': electricsFired,
        'casingsCracked': casingsCracked,
        'bricksFreed': bricksFreed,
        'lastRunScore': lastRunScore,
        'operatorUses': operatorUses,
        'runsByLength':
            runsByLength.map((k, v) => MapEntry(k.toString(), v)),
        'queue': queue.toJson(),
        'board': board.toJson(),
      };

  factory GameSession.fromJson(
    Map<String, dynamic> json,
    TileGenerator generator,
    LevelDef level,
  ) {
    final board = BoardModel.fromJson(json['board'] as Map<String, dynamic>);

    // The board restores its own id counter from the save; the generator
    // handed in here was built fresh and starts at zero. Left alone, every
    // tile it mints collides with one already on the board - and since the
    // render layer keys its components by tile id, the board and the screen
    // disagree from that point on and the view rebuilds itself, all
    // sixty-four components, after every single turn.
    generator.ids = board.ids;

    final session = GameSession(
      level: level,
      generator: generator,
      board: board,
    );

    // Override the queue that was primed in the constructor.
    final savedQueue = TileQueue.fromJson(json['queue'] as Map<String, dynamic>);
    for (var x = 0; x < savedQueue.width; x++) {
      final tile = savedQueue.peek(x);
      if (tile != null) session.queue.fill(x, tile);
    }

    session.phase = SessionPhase.values.byName(json['phase'] as String);
    session.score = json['score'] as int;
    session.movesUsed = json['movesUsed'] as int;
    session.equationsCleared = json['equationsCleared'] as int;
    session.longestChain = json['longestChain'] as int;
    session.bombsDetonated = json['bombsDetonated'] as int;
    session.electricsFired = json['electricsFired'] as int? ?? 0;
    session.casingsCracked = json['casingsCracked'] as int? ?? 0;
    session.bricksFreed = json['bricksFreed'] as int? ?? 0;
    session.lastRunScore = json['lastRunScore'] as int;

    if (json['operatorUses'] != null) {
      session.operatorUses
          .addAll(Map<String, int>.from(json['operatorUses'] as Map));
    }
    if (json['runsByLength'] != null) {
      final runs = json['runsByLength'] as Map;
      for (final entry in runs.entries) {
        session.runsByLength[int.parse(entry.key.toString())] =
            entry.value as int;
      }
    }
    // The restored score decides the stage, so this must come after it is set.
    session._applyRamp();
    return session;
  }
}
