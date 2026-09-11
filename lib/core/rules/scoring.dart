/// Scoring rules for a completed equation.
///
/// Ported from `easy-mathriss/lib/game/math_parser.dart:251-299`. The shape of
/// the formula is deliberately unchanged so that scores stay comparable between
/// the two games:
///
///   * complexity multipliers stack **multiplicatively**
///     (compound comparison x3, exponent x4, multiply/divide x5)
///   * length tiers are added **after** the multiplier, never scaled by it
///
/// A bare three-cell match such as `1=1` therefore scores 3 - deliberately
/// near-worthless, so players hunt for longer runs instead of farming trivia.
library;

/// The set of comparison operators built from two adjacent cells.
const Set<String> compoundComparisons = {'<=', '>=', '=>', '=<', '!='};

/// Outcome of scoring a single equation.
class ScoreResult {
  const ScoreResult(this.score, this.feedback);

  final int score;

  /// Celebration string for the longer tiers; empty for a plain match.
  final String feedback;
}

/// Scores an equation spanning [cells] whose comparison operator is [compOp].
///
/// [cells] is the raw glyph run, so a compound comparison occupies two entries.
ScoreResult scoreEquation(List<String> cells, String compOp) {
  var hasMultiplyOrDivide = false;
  var hasExponent = false;
  for (final cell in cells) {
    if (cell == '*' || cell == '/') hasMultiplyOrDivide = true;
    if (cell == '^') hasExponent = true;
  }
  final hasCompound = compoundComparisons.contains(compOp);

  var multiplier = 1;
  if (hasCompound) multiplier *= 3;
  if (hasExponent) multiplier *= 4;
  if (hasMultiplyOrDivide) multiplier *= 5;

  final totalCells = cells.length;
  var score = totalCells * multiplier;

  // Tiered length bonuses, stacked: cells from the 4th add +1, from the 6th a
  // further +2, from the 11th a further +5.
  var feedback = '';
  if (totalCells > 3) {
    score += (totalCells - 3) * 1;
    feedback = 'GOOD JOB! \u{1F44D}';
  }
  if (totalCells > 5) {
    score += (totalCells - 5) * 2;
    feedback = 'EXCELLENT! \u{1F31F}';
  }
  if (totalCells > 10) {
    score += (totalCells - 10) * 5;
    feedback = 'OH MY GOD! \u{1F631}';
  }

  return ScoreResult(score, feedback);
}

/// Scores a bomb detonation covering [cellCount] cells.
///
/// A blast takes no aim, so it pays a flat rate per cell rather than earning the
/// equation multipliers. It keeps the same escalating-tier shape, so a bomb that
/// goes off in a crowded row still reads as an event.
ScoreResult scoreBlast(int cellCount) {
  // Tiers and wording lifted from the bomb branch of
  // `easy-mathriss/lib/game/components/board.dart`, so a blast reads the same
  // in both games.
  var score = cellCount * 3;
  var feedback = 'BOOM BOOM! \u{1F4A5}';
  if (cellCount > 3) {
    feedback = 'BOOM! GOOD JOB! \u{1F4A5}\u{1F44D}';
  }
  if (cellCount > 5) {
    score += (cellCount - 5) * 2;
    feedback = 'BOOM! EXCELLENT! \u{1F4A5}\u{1F31F}';
  }
  if (cellCount > 10) {
    score += (cellCount - 10) * 5;
    feedback = 'MEGA BOOM! OH MY GOD! \u{1F4A5}\u{1F631}';
  }
  return ScoreResult(score, feedback);
}

/// Scores an electric discharge that took out [cellCount] bricks.
///
/// Shaped like [scoreBlast] - flat per cell, escalating tiers - because it
/// takes no aim either. The base rate is higher: a bomb always clears a full
/// cross whatever it is swapped into, while an electric's haul depends on how
/// many of one glyph happen to be out there, and half the time that is three
/// or four bricks scattered across the board.
///
/// The tiers sit lower than the blast's for the same reason. Fourteen matching
/// bricks is a far rarer event than a fourteen-cell cross.
ScoreResult scoreElectric(int cellCount) {
  var score = cellCount * 4;
  var feedback = 'ZAP! \u{26A1}';
  if (cellCount > 4) {
    feedback = 'ZAP! GOOD JOB! \u{26A1}\u{1F44D}';
  }
  if (cellCount > 8) {
    score += (cellCount - 8) * 3;
    feedback = 'CHAIN LIGHTNING! \u{26A1}\u{1F31F}';
  }
  if (cellCount > 12) {
    score += (cellCount - 12) * 6;
    feedback = 'THUNDERSTRUCK! \u{26A1}\u{1F631}';
  }
  return ScoreResult(score, feedback);
}

/// Scores one impact on an encased brick.
///
/// [armorLeft] is what the casing is down to *after* the hit, so zero means
/// the brick came free. Freeing it is worth most of the value: cracking a
/// diamond halfway is progress, but it is the release that gives the player a
/// cell back.
ScoreResult scoreCrack(int armorLeft) {
  if (armorLeft > 0) return const ScoreResult(2, '');
  return const ScoreResult(8, 'BROKEN OUT! \u{1F48E}');
}
