/// How a run gets harder as the score climbs. Pure Dart.
///
/// The shipped levels are tuned one at a time and never move. Endless has no
/// such structure - it is one board forever - so its difficulty has to come
/// from somewhere, and the only honest signal available is the score.
///
/// Two dials turn together here:
///
///   * the comparison mix widens away from `=` toward `<` and `>`
///   * obstacle bricks - stone, diamond, electric - start arriving
///
/// The plan behind this expected them to pull against each other, with the
/// obstacles taking back the playability the widened mix hands out.
/// `dart run tool/tune_weights.dart stages` says otherwise, and the shipped
/// table follows the measurement rather than the plan: **obstacles do not make
/// this board harder.** A bomb or an electric makes every adjacent swap legal,
/// which postpones deadlock on its own; a casing blocks matches, which slows
/// the drain on the comparison stock the board actually runs out of. Raising
/// the obstacle budget measurably *lengthens* runs.
///
/// So the budgets here are chosen for how the board reads - about one brick in
/// fifty at the opening, one in eight at the top - and the ramp's real effect
/// is that a deep run is richer and pays better, not that it is crueller.
/// Score per move runs 129 at the opening to 197 at the top.
///
/// The third dial, [DifficultyStage.comparisonCorrection], is what makes the
/// first one actually reach the board. Weights decide what is *drawn*; what
/// gets *consumed* decides what is left, and matches eat inequalities far
/// faster than equality. Without the correction a 50% draw settles into a 78%
/// board and the widening is invisible.
library;

import '../board/tile_generator.dart';

/// One rung of the ramp.
class DifficultyStage {
  const DifficultyStage({
    required this.fromScore,
    required this.name,
    required this.weights,
    this.comparisonCorrection = 0,
    this.maxObstacles = 4,
    this.maxEncased = 0,
    this.maxDiamonds = 0,
    this.encasedChance = 0,
    this.electricChance = 0,
  });

  /// Lowest score at which this stage applies.
  final int fromScore;

  /// Shown in the HUD when the stage changes. Short: it is a pip, not a label.
  final String name;

  final TileWeights weights;

  /// How hard the comparison mix is nudged toward [weights] on this stage.
  ///
  /// Zero is a plain weighted draw, and it is the default so that every level
  /// on [DifficultyRamp.flat] keeps exactly the composition it was tuned
  /// against.
  ///
  /// Above zero, a top-up favours whichever comparison glyph the board is
  /// short of. This exists because the draw alone does not decide a board's
  /// composition - what gets *consumed* decides it too, and matches eat `<`
  /// and `>` far faster than `=` because an inequality between two random
  /// numbers is true about half the time while equality almost never is. Left
  /// uncorrected, a 50% draw settles into a 78% board.
  ///
  /// The nudge is bounded on purpose. The target is not actually reachable, so
  /// a hard correction saturates: every top-up becomes an inequality, and an
  /// inequality dropped into a hole completes a true statement often enough
  /// that the board starts cascading on every refill. Measured unbounded, the
  /// shipped tiers went from 60 points a move to 5,500.
  final double comparisonCorrection;

  /// Most non-tokenizing bricks - bombs, electrics and encased together -
  /// allowed on the board at once.
  ///
  /// The load-bearing difficulty dial of the whole ramp, and the one the
  /// tuning tool actually binds on. Each of these is a cell no equation can
  /// run through, so this is a direct statement of how much of the board is
  /// unavailable. Four of sixty-four is roughly what the shipped build already
  /// reaches with bombs alone.
  final int maxObstacles;

  /// Most encased bricks allowed on the board at once, casings of any depth.
  final int maxEncased;

  /// Of those, how many may be diamonds. Never more than [maxEncased].
  final int maxDiamonds;

  /// Chance a refilled brick arrives encased, once the cap allows it.
  final double encasedChance;

  /// Chance a refilled cell arrives as an electric.
  final double electricChance;

  /// The opening stage, and the whole of every hand-tuned level.
  ///
  /// Weights here are exactly the ones the shipped build measured, so a level
  /// on [DifficultyRamp.flat] behaves identically to the build before the ramp
  /// existed.
  static const warmUp = DifficultyStage(
    fromScore: 0,
    name: 'WARM-UP',
    weights: TileWeights(),
  );
}

/// An ascending list of [DifficultyStage]s, keyed on score.
class DifficultyRamp {
  const DifficultyRamp(this.stages);

  /// Ordered by [DifficultyStage.fromScore], ascending. The first entry must
  /// start at zero.
  final List<DifficultyStage> stages;

  /// Index of the stage a run at [score] is in.
  int indexFor(int score) {
    var index = 0;
    for (var i = 1; i < stages.length; i++) {
      if (score < stages[i].fromScore) break;
      index = i;
    }
    return index;
  }

  DifficultyStage stageFor(int score) => stages[indexFor(score)];

  /// No ramp at all: one stage, today's numbers, no obstacles.
  ///
  /// The default for every [LevelDef], because all twenty shipped levels were
  /// tuned against a measured move count and dropping obstacles into them
  /// would invalidate that work.
  static const flat = DifficultyRamp([DifficultyStage.warmUp]);

  /// The endless ramp.
  ///
  /// `=` starts at three sevenths of the comparison budget and ends at one
  /// fifth of it. That is the complaint this exists to answer: with `!` absent
  /// from every shipped tier, the old `4:1:1` split gave `=` **four sixths** of
  /// the comparison share - 14% of the whole board, about nine cells of
  /// sixty-four.
  ///
  /// The comparison share itself falls as the mix widens, because inequalities
  /// buy far more legal moves per glyph than equality does. Arithmetic takes
  /// what comparison gives up, so runs get longer and more interesting rather
  /// than merely more frequent.
  static const endless = DifficultyRamp([
    DifficultyStage(
      fromScore: 0,
      name: 'WARM-UP',
      comparisonCorrection: 1.6,
      weights: TileWeights(
        comparisonWeights: {'=': 2.5, '<': 1.25, '>': 1.25, '!': 1},
      ),
    ),
    DifficultyStage(
      fromScore: 500,
      comparisonCorrection: 1.6,
      name: 'MIXED',
      weights: TileWeights(
        digitShare: 0.670,
        arithmeticShare: 0.125,
        comparisonShare: 0.205,
        comparisonWeights: {'=': 2, '<': 1.5, '>': 1.5, '!': 1},
      ),
      maxObstacles: 7,
      maxEncased: 5,
      encasedChance: 0.10,
    ),
    DifficultyStage(
      fromScore: 4000,
      comparisonCorrection: 1.6,
      name: 'CROWDED',
      weights: TileWeights(
        digitShare: 0.665,
        arithmeticShare: 0.140,
        comparisonShare: 0.195,
        arithmeticWeights: {'+': 3, '-': 3, '*': 1.4, '/': 1.2, '^': 1},
        comparisonWeights: {'=': 1.5, '<': 1.75, '>': 1.75, '!': 1},
      ),
      maxObstacles: 9,
      maxEncased: 7,
      maxDiamonds: 3,
      encasedChance: 0.14,
      electricChance: 0.010,
    ),
    DifficultyStage(
      fromScore: 12000,
      comparisonCorrection: 1.6,
      name: 'EXPERT',
      weights: TileWeights(
        digitShare: 0.660,
        arithmeticShare: 0.150,
        comparisonShare: 0.190,
        arithmeticWeights: {'+': 2, '-': 2, '*': 1.5, '/': 1.2, '^': 1},
        comparisonWeights: {'=': 1, '<': 2, '>': 2, '!': 1},
      ),
      maxObstacles: 11,
      maxEncased: 9,
      maxDiamonds: 4,
      encasedChance: 0.18,
      electricChance: 0.016,
    ),
  ]);
}
