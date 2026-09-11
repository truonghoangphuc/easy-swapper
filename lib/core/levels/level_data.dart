/// The shipped level list.
///
/// Pure data, so tuning a level never means touching engine code. Difficulty is
/// pushed by three dials, in roughly this order:
///
///   1. the operator tier, which widens the alphabet
///   2. the move budget
///   3. objectives that ask for something other than raw score, including
///      `ClearLongEquations` for length
///
/// Every level runs at `minRunLength: 3`. Raising it to 5 was the original plan
/// and it does not survive the operator cap: a five-cell run needs two operators
/// at an exact spacing, and with operators held under a third of the board
/// `dart run tool/tune_weights.dart playout` measures a run dying of deadlock
/// after about twelve moves, against eighty to a hundred and thirty at
/// `minRunLength: 3`. Since a deadlock now wipes the player's score, that made
/// nine of these twenty levels unplayable. Length is encouraged by objectives
/// and by the scoring tiers instead, neither of which can strand the board.
library;

import 'difficulty_ramp.dart';
import 'level_def.dart';

/// Levels 1 through 20, in play order.
const List<LevelDef> levels = [
  // --- Tier 1: addition, subtraction, equality. Teach the swap. ---
  LevelDef(
    id: 1,
    moves: 25,
    minRunLength: 3,
    operators: OperatorSet.tier1,
    objectives: [ReachScore(120)],
    starThresholds: [120, 220, 340],
  ),
  LevelDef(
    id: 2,
    moves: 25,
    minRunLength: 3,
    operators: OperatorSet.tier1,
    objectives: [ClearEquations(12)],
    starThresholds: [140, 250, 380],
  ),
  LevelDef(
    id: 3,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier1,
    objectives: [ReachScore(260)],
    starThresholds: [260, 400, 560],
  ),
  LevelDef(
    id: 4,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier1,
    // First nudge toward longer runs, while three-cell matches still score.
    objectives: [ClearLongEquations(4, 5)],
    starThresholds: [200, 340, 500],
  ),
  LevelDef(
    id: 5,
    moves: 20,
    minRunLength: 3,
    operators: OperatorSet.tier1,
    objectives: [ReachScore(380), ClearEquations(14)],
    starThresholds: [380, 520, 700],
  ),

  // --- Tier 2: inequalities. Matches get much easier, so tighten elsewhere. ---
  LevelDef(
    id: 6,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [UseOperator('<', 6)],
    starThresholds: [220, 360, 520],
  ),
  LevelDef(
    id: 7,
    moves: 20,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [ReachScore(420)],
    starThresholds: [420, 580, 780],
  ),
  LevelDef(
    id: 8,
    moves: 20,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [UseOperator('>', 8), ClearEquations(16)],
    starThresholds: [300, 460, 660],
  ),
  LevelDef(
    id: 9,
    // A wider budget so the equation-count goal is reachable without rushing.
    moves: 26,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [ClearEquations(8)],
    starThresholds: [260, 420, 600],
  ),
  LevelDef(
    id: 10,
    moves: 24,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [ReachScore(480)],
    starThresholds: [480, 660, 880],
  ),
  LevelDef(
    id: 11,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [ClearLongEquations(5, 6)],
    starThresholds: [420, 600, 820],
  ),
  LevelDef(
    id: 12,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier2,
    objectives: [ReachScore(560), UseOperator('=', 10)],
    starThresholds: [560, 760, 1000],
  ),

  // --- Tier 3: multiply and divide, worth a 5x score multiplier. ---
  LevelDef(
    id: 13,
    moves: 24,
    minRunLength: 3,
    operators: OperatorSet.tier3,
    objectives: [UseOperator('*', 5)],
    starThresholds: [500, 800, 1200],
  ),
  LevelDef(
    id: 14,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier3,
    objectives: [ReachScore(900)],
    starThresholds: [900, 1300, 1800],
  ),
  LevelDef(
    id: 15,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier3,
    objectives: [ClearEquations(10)],
    starThresholds: [700, 1100, 1600],
  ),
  LevelDef(
    id: 16,
    moves: 20,
    minRunLength: 3,
    operators: OperatorSet.tier3,
    objectives: [UseOperator('/', 4), ReachScore(800)],
    starThresholds: [800, 1200, 1700],
  ),
  LevelDef(
    id: 17,
    moves: 20,
    minRunLength: 3,
    operators: OperatorSet.tier3,
    objectives: [ClearLongEquations(6, 6)],
    starThresholds: [900, 1400, 2000],
  ),

  // --- Tier 4: exponents and compound comparisons. ---
  LevelDef(
    id: 18,
    moves: 24,
    minRunLength: 3,
    operators: OperatorSet.tier4,
    objectives: [UseOperator('^', 3)],
    starThresholds: [800, 1300, 1900],
  ),
  LevelDef(
    id: 19,
    moves: 22,
    minRunLength: 3,
    operators: OperatorSet.tier4,
    objectives: [ReachScore(1400)],
    starThresholds: [1400, 2000, 2800],
  ),
  LevelDef(
    id: 20,
    moves: 20,
    minRunLength: 3,
    operators: OperatorSet.tier4,
    objectives: [ReachScore(1800), ClearLongEquations(4, 7)],
    starThresholds: [1800, 2600, 3600],
  ),
];

/// Endless mode: no move budget and no objectives. A deadlock wipes the score
/// and deals a fresh board, so the run only ever ends when the player stops.
///
/// The one mode on a difficulty ramp. With no level boundaries to pace it, the
/// score is the only honest signal of how far in the player is, so that is
/// what widens the comparison mix and lets the obstacle bricks in.
const LevelDef endlessLevel = LevelDef(
  id: 0,
  moves: -1,
  minRunLength: 3,
  operators: OperatorSet.tier3,
  objectives: [],
  starThresholds: [1000, 3000, 6000],
  ramp: DifficultyRamp.endless,
);

/// Looks up a level by its [id], or null if there is no such level.
LevelDef? levelById(int id) {
  if (id == 0) return endlessLevel;
  for (final level in levels) {
    if (level.id == id) return level;
  }
  return null;
}
