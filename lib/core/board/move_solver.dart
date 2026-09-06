/// Exhaustive legal-move search. Pure Dart.
///
/// This has no counterpart in easy-mathriss and is the component the whole game
/// leans on. In a colour-matching puzzle any three like tiles match, so legal
/// moves are dense and a deadlock is rare. Valid *equations* are rare, so a
/// randomly refilled board deadlocks often and silently. Every part of the game
/// that has to know "is this board still playable" routes through here:
///
///   * deadlock detection after each settle, which triggers a reshuffle
///   * board generation, which rejects any layout below a move floor
///   * the idle hint
///   * difficulty tuning, by logging the move count per settle
///
/// Cost on the default 8x8 board is about 112 candidate swaps times four
/// rescanned lines - a few milliseconds, safe to run off the render path.
library;

import '../rules/scoring.dart';
import 'board_model.dart';
import 'tile.dart';

/// A swap that produces at least one match, and what it would be worth.
class Move {
  const Move({
    required this.a,
    required this.b,
    required this.score,
    required this.matches,
    this.detonates = false,
  });

  final Coord a;
  final Coord b;

  /// Total score the swap is worth, before cascades. Includes the blast when
  /// [detonates] is set.
  final int score;

  final List<BoardMatch> matches;

  /// True when one of the two cells holds a bomb, so the swap is legal on its
  /// own even though it completes no equation.
  final bool detonates;

  @override
  String toString() =>
      'Move($a<->$b, $score${detonates ? ", detonates" : ""})';
}

/// Every legal swap on [board], unordered.
List<Move> findAllLegalMoves(BoardModel board, {int minRunLength = 3}) {
  final moves = <Move>[];
  for (final (a, b) in board.allSwapPairs()) {
    final move = _tryswap(board, a, b, minRunLength);
    if (move != null) moves.add(move);
  }
  return moves;
}

/// Whether [board] has any legal swap at all.
///
/// Short-circuits, so prefer this to `findAllLegalMoves(...).isNotEmpty` when
/// the answer is all that matters - generation retries call it in a loop.
bool hasAnyLegalMove(BoardModel board, {int minRunLength = 3}) {
  for (final (a, b) in board.allSwapPairs()) {
    if (_tryswap(board, a, b, minRunLength) != null) return true;
  }
  return false;
}

/// The highest-scoring legal move, or `null` on a deadlocked board.
///
/// Drives the idle hint.
Move? findBestMove(BoardModel board, {int minRunLength = 3}) {
  Move? best;
  for (final (a, b) in board.allSwapPairs()) {
    final move = _tryswap(board, a, b, minRunLength);
    if (move == null) continue;
    if (best == null || move.score > best.score) best = move;
  }
  return best;
}

/// Applies a swap, rescans only the affected lines, and undoes it.
///
/// Mutating and restoring the real board beats copying it: the solver runs this
/// a hundred times per settle, and a copy per candidate would dominate the cost.
Move? _tryswap(BoardModel board, Coord a, Coord b, int minRunLength) {
  // A bomb detonates on any swap, so it is always a legal move. This has to be
  // checked here and not just in the session: deadlock detection runs through
  // this function, and a board holding a bomb is never actually stuck.
  final bombScore = _bombSwapScore(board, a, b);

  board.swap(a, b);
  final matches = board.findMatchesAffectedBy(a, b, minRunLength: minRunLength);
  board.swap(a, b);

  if (matches.isEmpty && bombScore == null) return null;
  final score =
      matches.fold<int>(bombScore ?? 0, (sum, m) => sum + m.score);
  return Move(
    a: a,
    b: b,
    score: score,
    matches: matches,
    detonates: bombScore != null,
  );
}

/// Score of the blast a swap of [a] and [b] would set off, or null if neither
/// cell holds a bomb.
int? _bombSwapScore(BoardModel board, Coord a, Coord b) {
  final aBomb = board.atCoord(a)?.isBomb ?? false;
  final bBomb = board.atCoord(b)?.isBomb ?? false;
  if (!aBomb && !bBomb) return null;

  // Each bomb ends up where the other tile was.
  final cells = <Coord>{};
  if (aBomb) cells.addAll(board.blastCells(b));
  if (bBomb) cells.addAll(board.blastCells(a));
  return scoreBlast(cells.length).score;
}
