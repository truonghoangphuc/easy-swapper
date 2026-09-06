import 'package:easy_swapper/core/math/expression_engine.dart';
import 'package:easy_swapper/core/rules/scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateExpression', () {
    test('applies the four basic operators', () {
      expect(evaluateExpression([10.0, '+', 5.0]), 15.0);
      expect(evaluateExpression([10.0, '-', 5.0]), 5.0);
      expect(evaluateExpression([10.0, '*', 5.0]), 50.0);
      expect(evaluateExpression([10.0, '/', 5.0]), 2.0);
    });

    test('respects precedence over left-to-right order', () {
      // The regression easy-mathriss encodes: 1 + 2 * 3 is 7, not 9.
      expect(evaluateExpression([1.0, '+', 2.0, '*', 3.0]), 7.0);
      expect(evaluateExpression([10.0, '-', 4.0, '/', 2.0]), 8.0);
    });

    test('evaluates exponents right-to-left and above multiplication', () {
      expect(evaluateExpression([2.0, '^', 3.0]), 8.0);
      expect(evaluateExpression([2.0, '^', 3.0, '^', 2.0]), 512.0);
      expect(evaluateExpression([2.0, '*', 3.0, '^', 2.0]), 18.0);
    });

    test('rejects malformed token lists', () {
      expect(evaluateExpression([]), isNull);
      expect(evaluateExpression(['+', 1.0]), isNull);
      expect(evaluateExpression([1.0, '+']), isNull);
      expect(evaluateExpression([1.0, '/', 0.0]), isNull, reason: 'divide by zero');
      expect(evaluateExpression([1.0, 2.0]), isNull, reason: 'no operator');
    });
  });

  group('tokenize', () {
    List<dynamic>? tokensOf(List<String?> cells) {
      final result = tokenize(cells, List.generate(cells.length, (i) => i));
      return result == null ? null : result[0] as List<dynamic>;
    }

    test('merges adjacent digits into one number', () {
      expect(tokensOf(['1', '9', '9']), [199.0]);
      expect(tokensOf(['1', '2', '+', '3']), [12.0, '+', 3.0]);
    });

    test('fuses two-cell comparison operators', () {
      expect(tokensOf(['1', '<', '=', '2']), [1.0, '<=', 2.0]);
      expect(tokensOf(['1', '!', '=', '2']), [1.0, '!=', 2.0]);
      expect(tokensOf(['1', '=', '<', '2']), [1.0, '=<', 2.0]);
    });

    test('rejects a bare bang and unknown glyphs', () {
      expect(tokensOf(['1', '!', '2']), isNull);
      expect(tokensOf(['1', '@', '2']), isNull);
    });

    test('maps tokens back to their source cells', () {
      final result = tokenize(['1', '9', '+', '2'], [4, 5, 6, 7]);
      expect(result, isNotNull);
      expect(result![1], [
        [4, 5],
        [6],
        [7],
      ]);
    });
  });

  group('findAllEquations - ported easy-mathriss cases', () {
    test('finds a simple addition surrounded by gaps', () {
      final matches =
          findAllEquations([null, '1', '+', '1', '=', '2', null, '9', '8']);
      expect(matches, hasLength(1));
      expect(matches.single.start, 1);
      expect(matches.single.end, 5);
      expect(matches.single.score, 7, reason: '5 cells + (5-3) tier bonus');
    });

    test('matches multi-digit numbers on both sides', () {
      final matches = findAllEquations(['1', '0', '=', '1', '0', null, null]);
      expect(matches, hasLength(1));
      expect(matches.single.start, 0);
      expect(matches.single.end, 4);
      expect(matches.single.score, 7);
    });

    test('matches a strict inequality', () {
      final matches = findAllEquations([null, '5', '>', '3', null, null]);
      expect(matches, hasLength(1));
      expect(matches.single.start, 1);
      expect(matches.single.end, 3);
    });

    test('multiplies the score for multiply and divide', () {
      final matches = findAllEquations(['2', '*', '3', '=', '6', null, null]);
      expect(matches.single.score, 27, reason: '5 cells x5, then +2 tier bonus');
    });

    test('prefers the longest correct run over a shorter true one', () {
      // 199 > 200 is false, so the scan settles on 199 > 20.
      final matches = findAllEquations(['1', '9', '9', '>', '2', '0', '0']);
      expect(matches, hasLength(1));
      expect(matches.single.start, 0);
      expect(matches.single.end, 5);
      expect(matches.single.score, 11);
    });
  });

  group('findAllEquations - swapper-specific behaviour', () {
    test('returns every disjoint match in one line', () {
      // The behaviour easy-mathriss lacks: its findEquations stopped at one.
      final matches = findAllEquations(['1', '=', '1', '5', '=', '5']);
      expect(matches, hasLength(2));
      expect(matches[0].start, 0);
      expect(matches[0].end, 2);
      expect(matches[1].start, 3);
      expect(matches[1].end, 5);
    });

    test('results come back in left-to-right order', () {
      final matches = findAllEquations(['1', '=', '1', '5', '=', '5']);
      expect(matches.map((m) => m.start), [0, 3]);
    });

    test('drops an overlapping candidate, keeping the leftmost on a tie', () {
      // Both 1=1 runs score 3 and share the middle cell.
      final matches = findAllEquations(['1', '=', '1', '=', '1']);
      expect(matches, hasLength(1));
      expect(matches.single.start, 0);
      expect(matches.single.end, 2);
    });

    test('keeps the higher-scoring run when two overlap', () {
      // 2*3=6 scores 27; the overlapping 6=6 would score 3.
      final matches = findAllEquations(['2', '*', '3', '=', '6', '=', '6']);
      expect(matches, hasLength(1));
      expect(matches.single.cells.join(), '2*3=6');
      expect(matches.single.score, 27);
    });

    test('minRunLength filters out short runs', () {
      final line = ['1', '=', '1', '2', '3', '4'];
      expect(findAllEquations(line, minRunLength: 3), hasLength(1));
      expect(findAllEquations(line, minRunLength: 5), isEmpty);
    });

    test('a run of five still matches when minRunLength is five', () {
      final matches =
          findAllEquations(['1', '+', '1', '=', '2', '7'], minRunLength: 5);
      expect(matches, hasLength(1));
      expect(matches.single.cells.join(), '1+1=2');
    });

    test('a null cell breaks a run rather than being skipped over', () {
      expect(findAllEquations(['1', '+', null, '1', '=', '2']), isEmpty);
    });

    test('two comparison operators do not form an equation', () {
      expect(findAllEquations(['1', '=', '1', '=', '1']).single.length, 3);
      expect(findAllEquations(['=', '=', '=']), isEmpty);
    });

    test('an unknown glyph aborts the run containing it', () {
      // Power-up tiles scan as null; a literal unknown glyph must behave the
      // same way so a special can never be consumed by an equation.
      expect(findAllEquations(['1', '+', '\u{1F4A3}', '=', '1']), isEmpty);
    });
  });

  group('scoreEquation', () {
    test('a bare three-cell match is deliberately near-worthless', () {
      expect(scoreEquation(['1', '=', '1'], '=').score, 3);
    });

    test('complexity multipliers stack multiplicatively', () {
      // 6 cells at compound x3 times divide x5 = 90 base, then +3 and +2 tiers.
      expect(scoreEquation(['6', '/', '2', '!', '=', '2'], '!=').score,
          6 * 15 + 3 + 2);
    });

    test('length tiers are added after the multiplier, not scaled by it', () {
      final four = scoreEquation(['1', '+', '1', '=', '2'], '=');
      expect(four.score, 5 + 2);
      expect(four.feedback, contains('GOOD JOB'));
    });

    test('feedback escalates with length', () {
      expect(scoreEquation(List.filled(3, '1'), '=').feedback, isEmpty);
      expect(scoreEquation(List.filled(5, '1'), '=').feedback, contains('GOOD JOB'));
      expect(scoreEquation(List.filled(7, '1'), '=').feedback, contains('EXCELLENT'));
      expect(scoreEquation(List.filled(12, '1'), '=').feedback, contains('OH MY GOD'));
    });
  });
}
