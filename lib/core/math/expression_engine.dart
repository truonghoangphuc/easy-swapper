/// Pure-Dart rules engine for Easy Swapper.
///
/// Ported from `easy-mathriss/lib/game/math_parser.dart`, with one substantive
/// change: [findAllEquations] returns **every** non-overlapping match in a line,
/// where the original `findEquations` returned at most one. Tetris only ever
/// lands one piece at a time; a swap-and-cascade board has to resolve the whole
/// grid at once.
///
/// This library imports nothing but `dart:math` on purpose. Keeping the rules
/// free of Flutter and Flame is what makes the solver cheap to property-test.
library;

import 'dart:math' as math;

import '../rules/scoring.dart';

/// Floating point slack for equality and ordering comparisons.
const double epsilon = 1e-9;

/// Single-cell arithmetic operators.
const List<String> arithmeticOps = ['+', '-', '*', '/', '^'];

/// Operators that may absorb a following `=` to form a compound comparison.
const List<String> compoundableOps = ['<', '>', '!'];

/// True for a single-character glyph in the range 0-9.
///
/// A code-unit test rather than a regex: this sits in the innermost loop of the
/// solver, which tokenizes tens of thousands of runs per board scan.
bool isDigitGlyph(String? cell) =>
    cell != null &&
    cell.length == 1 &&
    cell.codeUnitAt(0) >= 0x30 &&
    cell.codeUnitAt(0) <= 0x39;

/// One valid equation found inside a single line of cells.
class EquationMatch {
  const EquationMatch({
    required this.start,
    required this.end,
    required this.score,
    required this.cells,
    required this.feedback,
    required this.comparison,
  });

  /// Index of the first cell of the run, within the scanned line.
  final int start;

  /// Index of the last cell of the run, inclusive.
  final int end;

  final int score;

  /// The raw glyphs making up the run.
  final List<String> cells;

  final String feedback;

  /// The comparison operator that split the run, e.g. `=` or `<=`.
  final String comparison;

  int get length => end - start + 1;

  /// True when this run shares at least one cell with [other].
  bool overlaps(EquationMatch other) => start <= other.end && other.start <= end;

  @override
  String toString() => 'EquationMatch(${cells.join()} @$start-$end = $score)';
}

/// Tokenizes [cells], merging adjacent digits into one number and fusing
/// two-cell comparison operators.
///
/// Returns `[tokens, tokenIndices]` where `tokens` holds `double`s and operator
/// `String`s, and `tokenIndices[i]` lists the [cellIndices] entries that token
/// was built from. Returns `null` if any glyph is unrecognised, which is how a
/// special tile aborts a scan.
List<dynamic>? tokenize(List<String?> cells, List<int> cellIndices) {
  final tokens = <dynamic>[];
  final tokenIndices = <List<int>>[];

  var i = 0;
  while (i < cells.length) {
    final cell = cells[i];
    if (cell == null || cell.isEmpty) {
      i++;
      continue;
    }

    if (isDigitGlyph(cell)) {
      // Adjacent digits read as a single multi-digit number: 1,9,9 becomes 199.
      var numStr = cell;
      final indices = [cellIndices[i]];
      var j = i + 1;
      while (j < cells.length && isDigitGlyph(cells[j])) {
        numStr += cells[j]!;
        indices.add(cellIndices[j]);
        j++;
      }
      tokens.add(double.parse(numStr));
      tokenIndices.add(indices);
      i = j;
    } else if (arithmeticOps.contains(cell)) {
      tokens.add(cell);
      tokenIndices.add([cellIndices[i]]);
      i++;
    } else if (compoundableOps.contains(cell)) {
      if (i + 1 < cells.length && cells[i + 1] == '=') {
        tokens.add('$cell=');
        tokenIndices.add([cellIndices[i], cellIndices[i + 1]]);
        i += 2;
      } else {
        // A bare bang is only ever the prefix of the not-equal operator.
        if (cell == '!') return null;
        tokens.add(cell);
        tokenIndices.add([cellIndices[i]]);
        i++;
      }
    } else if (cell == '=') {
      // Reversed compounds are accepted too, matching easy-mathriss.
      if (i + 1 < cells.length && (cells[i + 1] == '<' || cells[i + 1] == '>')) {
        tokens.add('=${cells[i + 1]}');
        tokenIndices.add([cellIndices[i], cellIndices[i + 1]]);
        i += 2;
      } else {
        tokens.add(cell);
        tokenIndices.add([cellIndices[i]]);
        i++;
      }
    } else {
      return null;
    }
  }

  return [tokens, tokenIndices];
}

/// Evaluates an arithmetic token list with standard precedence and no
/// parentheses: exponent right-to-left, then multiply and divide, then add and
/// subtract.
///
/// Returns `null` for anything malformed, including a leading or trailing
/// operator and division by zero.
double? evaluateExpression(List<dynamic> tokens) {
  if (tokens.isEmpty) return null;

  final temp = List<dynamic>.from(tokens);

  var i = temp.length - 2;
  while (i >= 0) {
    if (temp[i] == '^') {
      if (i == 0 || i == temp.length - 1) return null;
      final left = temp[i - 1];
      final right = temp[i + 1];
      if (left is! double || right is! double) return null;
      temp.replaceRange(i - 1, i + 2, [math.pow(left, right).toDouble()]);
      i = math.min(i - 1, temp.length - 2);
    } else {
      i--;
    }
  }

  i = 0;
  while (i < temp.length) {
    final token = temp[i];
    if (token == '*' || token == '/') {
      if (i == 0 || i == temp.length - 1) return null;
      final left = temp[i - 1];
      final right = temp[i + 1];
      if (left is! double || right is! double) return null;
      double result;
      if (token == '*') {
        result = left * right;
      } else {
        if (right == 0) return null;
        result = left / right;
      }
      temp.replaceRange(i - 1, i + 2, [result]);
      i--;
    } else {
      i++;
    }
  }

  i = 0;
  while (i < temp.length) {
    final token = temp[i];
    if (token == '+' || token == '-') {
      if (i == 0 || i == temp.length - 1) return null;
      final left = temp[i - 1];
      final right = temp[i + 1];
      if (left is! double || right is! double) return null;
      temp.replaceRange(i - 1, i + 2, [token == '+' ? left + right : left - right]);
      i--;
    } else {
      i++;
    }
  }

  if (temp.length == 1 && temp[0] is double) return temp[0] as double;
  return null;
}

/// True if [op] is a comparison operator, single or compound.
bool isComparisonOp(dynamic op) =>
    op == '=' ||
    op == '<' ||
    op == '>' ||
    op == '<=' ||
    op == '>=' ||
    op == '=>' ||
    op == '=<' ||
    op == '!=';

/// True if [left] and [right] satisfy the comparison [compOp].
bool comparisonHolds(String compOp, double left, double right) {
  switch (compOp) {
    case '=':
      return (left - right).abs() < epsilon;
    case '<':
      return left < right - epsilon;
    case '>':
      return left > right + epsilon;
    case '<=':
    case '=>':
      return left <= right + epsilon;
    case '>=':
    case '=<':
      return left >= right - epsilon;
    case '!=':
      return (left - right).abs() >= epsilon;
    default:
      return false;
  }
}

/// Every candidate equation in [line], including mutually overlapping ones.
///
/// Exposed mainly for tests; gameplay wants [findAllEquations].
List<EquationMatch> findCandidateEquations(
  List<String?> line, {
  int minRunLength = 3,
}) {
  final found = <EquationMatch>[];
  final indices = List<int>.generate(line.length, (i) => i);

  for (var start = 0; start + 2 < line.length; start++) {
    // The inner loop always begins at length 3 even when minRunLength is
    // higher. The break conditions below (unknown glyph, a second comparison
    // operator) have to be evaluated on the short prefixes to stay faithful to
    // the original scan; runs below the minimum are simply not recorded.
    for (var end = start + 2; end < line.length; end++) {
      final subCells = line.sublist(start, end + 1);
      if (subCells.contains(null) || subCells.any((c) => c!.isEmpty)) break;

      final result = tokenize(subCells, indices.sublist(start, end + 1));
      if (result == null) break;
      final tokens = result[0] as List<dynamic>;

      // Exactly one comparison operator, or the run is not an equation.
      var compIdx = -1;
      var tooMany = false;
      for (var k = 0; k < tokens.length; k++) {
        if (isComparisonOp(tokens[k])) {
          if (compIdx != -1) {
            tooMany = true;
            break;
          }
          compIdx = k;
        }
      }
      if (tooMany) break;
      if (compIdx == -1) continue;

      final compOp = tokens[compIdx] as String;
      final leftVal = evaluateExpression(tokens.sublist(0, compIdx));
      final rightVal = evaluateExpression(tokens.sublist(compIdx + 1));
      if (leftVal == null || rightVal == null) continue;
      if (!comparisonHolds(compOp, leftVal, rightVal)) continue;
      if (subCells.length < minRunLength) continue;

      final cells = subCells.cast<String>();
      final scored = scoreEquation(cells, compOp);
      found.add(EquationMatch(
        start: start,
        end: end,
        score: scored.score,
        cells: cells,
        feedback: scored.feedback,
        comparison: compOp,
      ));
    }
  }
  return found;
}

/// The non-overlapping set of equations in [line], preferring higher scores.
///
/// Candidates are resolved greedily: highest score first, ties broken by the
/// longer run and then the leftmost, and a candidate is accepted only if it
/// does not touch one already taken. Results come back in left-to-right order.
List<EquationMatch> findAllEquations(
  List<String?> line, {
  int minRunLength = 3,
}) {
  final candidates = findCandidateEquations(line, minRunLength: minRunLength);
  if (candidates.isEmpty) return const [];

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byLength = b.length.compareTo(a.length);
    if (byLength != 0) return byLength;
    return a.start.compareTo(b.start);
  });

  final accepted = <EquationMatch>[];
  for (final candidate in candidates) {
    if (accepted.any(candidate.overlaps)) continue;
    accepted.add(candidate);
  }
  accepted.sort((a, b) => a.start.compareTo(b.start));
  return accepted;
}
