/// Level definitions. Data, not logic, so tuning never touches the engine.
library;

import 'difficulty_ramp.dart';

/// The glyph alphabet available at a given difficulty tier.
///
/// Mirrors the level gating in `easy-mathriss/lib/game/block_generator.dart`,
/// but as data on the level rather than an `if` ladder on the level number.
class OperatorSet {
  const OperatorSet({required this.arithmetic, required this.comparison});

  final List<String> arithmetic;
  final List<String> comparison;

  /// True when this tier can produce two-cell operators such as `<=`.
  bool get allowsCompounds =>
      comparison.contains('<') || comparison.contains('>') || comparison.contains('!');

  /// Levels 1-5: addition and subtraction, equality only.
  static const tier1 = OperatorSet(arithmetic: ['+', '-'], comparison: ['=']);

  /// Levels 6-12: inequalities join in.
  static const tier2 =
      OperatorSet(arithmetic: ['+', '-'], comparison: ['=', '<', '>']);

  /// Levels 13-20: multiplication and division.
  static const tier3 = OperatorSet(
    arithmetic: ['+', '-', '*', '/'],
    comparison: ['=', '<', '>'],
  );

  /// Level 21 and up: exponents.
  ///
  /// `!` is deliberately absent. It is only ever the prefix of `!=`, so it
  /// needs an `=` immediately beside it to mean anything - and operators are no
  /// longer allowed to be generated side by side, which would leave every `!`
  /// on the board a dead cell the player could never use.
  static const tier4 = OperatorSet(
    arithmetic: ['+', '-', '*', '/', '^'],
    comparison: ['=', '<', '>'],
  );
}

/// What the player has to achieve to clear a level.
sealed class Objective {
  const Objective();

  /// Human-readable goal text for the HUD.
  String get label;
}

/// Reach a score threshold.
class ReachScore extends Objective {
  const ReachScore(this.target);

  final int target;

  @override
  String get label => 'Score $target';
}

/// Resolve a number of equations, of any length.
class ClearEquations extends Objective {
  const ClearEquations(this.count);

  final int count;

  @override
  String get label => 'Clear $count equations';
}

/// Resolve equations that use a particular glyph.
class UseOperator extends Objective {
  const UseOperator(this.glyph, this.count);

  final String glyph;
  final int count;

  @override
  String get label => 'Use $glyph x$count';
}

/// Resolve a number of equations of at least [minLength] cells.
class ClearLongEquations extends Objective {
  const ClearLongEquations(this.count, this.minLength);

  final int count;
  final int minLength;

  @override
  String get label => 'Clear $count runs of $minLength+';
}

/// A single playable level.
class LevelDef {
  const LevelDef({
    required this.id,
    required this.moves,
    required this.minRunLength,
    required this.operators,
    required this.objectives,
    required this.starThresholds,
    this.width = 8,
    this.height = 8,
    this.ramp = DifficultyRamp.flat,
  });

  final int id;

  /// Move budget, or -1 for endless.
  final int moves;

  /// Shortest run that counts as a match at this level.
  final int minRunLength;

  final OperatorSet operators;
  final List<Objective> objectives;

  /// Three ascending score cutoffs for one, two and three stars.
  final List<int> starThresholds;

  final int width;
  final int height;

  /// How the draw changes as the score climbs.
  ///
  /// Flat by default, and every one of the twenty shipped levels leaves it
  /// that way: each was tuned against a measured opening-move count, and a
  /// ramp that widened the comparison mix or dealt obstacles halfway through
  /// would quietly invalidate that work. Endless, which has no such structure
  /// to protect, is where the ramp earns its keep.
  final DifficultyRamp ramp;

  bool get isEndless => moves < 0;

  /// Stars earned for a final [score], 0 to 3.
  int starsFor(int score) {
    var stars = 0;
    for (final threshold in starThresholds) {
      if (score >= threshold) stars++;
    }
    return stars;
  }
}
