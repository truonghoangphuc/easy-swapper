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
    this.discharges = false,
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

  /// True when one of the two cells holds an electric, for the same reason.
  final bool discharges;

  @override
  String toString() => 'Move($a<->$b, $score'
      '${detonates ? ", detonates" : ""}'
      '${discharges ? ", discharges" : ""})';
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
  // An encased brick is pinned until its casing breaks, and the session will
  // refuse the swap. The check has to live here too, not only there: deadlock
  // detection runs through this function, so a solver that counted pinned
  // swaps would report a board as playable while the player has nothing left
  // to play - and a deadlock wipes the score.
  if (!canSwapPair(board.atCoord(a), board.atCoord(b))) return null;

  // A bomb detonates on any swap, and an electric discharges on any swap, so
  // either makes the swap legal on its own. Same reasoning as above: a board
  // holding one is never actually stuck.
  final bombScore = _bombSwapScore(board, a, b);
  final electricScore = _electricSwapScore(board, a, b);

  board.swap(a, b);
  final matches = board.findMatchesAffectedBy(a, b, minRunLength: minRunLength);
  board.swap(a, b);

  if (matches.isEmpty && bombScore == null && electricScore == null) {
    return null;
  }
  final score = matches.fold<int>(
    (bombScore ?? 0) + (electricScore ?? 0),
    (sum, m) => sum + m.score,
  );
  return Move(
    a: a,
    b: b,
    score: score,
    matches: matches,
    detonates: bombScore != null,
    discharges: electricScore != null,
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

/// Score of the discharge a swap of [a] and [b] would set off, or null if
/// neither cell holds an electric.
///
/// Mirrors [_bombSwapScore], including the "each one ends up where the other
/// was" detail: the electric fires from its destination, and its target is
/// whatever it displaced.
int? _electricSwapScore(BoardModel board, Coord a, Coord b) {
  final tileA = board.atCoord(a);
  final tileB = board.atCoord(b);
  final aElectric = tileA?.isElectric ?? false;
  final bElectric = tileB?.isElectric ?? false;
  if (!aElectric && !bElectric) return null;

  final sweep = electricSweep(
    board,
    partner: aElectric ? tileB : tileA,
    bothElectric: aElectric && bElectric,
  );
  // Plus the electrics themselves, which are spent either way.
  final spent = (aElectric ? 1 : 0) + (bElectric ? 1 : 0);
  return scoreElectric(sweep.cells.length + spent).score;
}

/// What one electric discharge reaches.
class ElectricSweep {
  const ElectricSweep({required this.glyph, required this.cells});

  /// The glyph it swept for, or null when it took every digit.
  final String? glyph;

  final Set<Coord> cells;
}

/// The cells an electric would take out, given the brick it was swapped with.
///
/// Shared with the session so the hint and the resolution can never disagree
/// about what the power-up does.
///
///   * an ordinary partner - digit or operator, encased or not - is targeted
///     by its visible glyph
///   * a partner with no glyph of its own (a bomb, or another electric) falls
///     back to the most common glyph on the board, which is deterministic
///   * two electrics together take every digit, the classic double
///
/// Encased bricks are included. What happens to them on arrival is the
/// session's call, and it is damage rather than destruction.
ElectricSweep electricSweep(
  BoardModel board, {
  required Tile? partner,
  required bool bothElectric,
}) {
  if (bothElectric) {
    final cells = <Coord>{};
    for (var y = 0; y < board.height; y++) {
      for (var x = 0; x < board.width; x++) {
        if (board.at(x, y)?.kind == TileKind.digit) cells.add(Coord(x, y));
      }
    }
    return ElectricSweep(glyph: null, cells: cells);
  }

  final glyph = (partner != null && !partner.isSpecial)
      ? partner.glyph
      : board.mostCommonGlyph();
  return ElectricSweep(
    glyph: glyph,
    cells: glyph == null ? <Coord>{} : board.cellsMatching(glyph),
  );
}
