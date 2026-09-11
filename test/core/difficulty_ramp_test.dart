import 'dart:math';

import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/board/tile_generator.dart';
import 'package:easy_swapper/core/levels/difficulty_ramp.dart';
import 'package:easy_swapper/core/levels/level_data.dart';
import 'package:easy_swapper/core/levels/level_def.dart';
import 'package:easy_swapper/core/session/game_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// How often each comparison glyph comes out of [generator], over [draws].
Map<String, int> comparisonMix(TileGenerator generator, {int draws = 20000}) {
  final counts = <String, int>{};
  for (var i = 0; i < draws; i++) {
    final glyph = generator.nextComparison().glyph;
    counts.update(glyph, (v) => v + 1, ifAbsent: () => 1);
  }
  return counts;
}

void main() {
  group('stage lookup', () {
    const ramp = DifficultyRamp.endless;

    test('the boundaries land exactly where the table says', () {
      expect(ramp.indexFor(0), 0);
      expect(ramp.indexFor(499), 0);
      expect(ramp.indexFor(500), 1);
      expect(ramp.indexFor(3999), 1);
      expect(ramp.indexFor(4000), 2);
      expect(ramp.indexFor(11999), 2);
      expect(ramp.indexFor(12000), 3);
      expect(ramp.indexFor(1 << 30), 3, reason: 'the last stage is the last');
    });

    test('the table is ordered and starts at zero', () {
      expect(ramp.stages.first.fromScore, 0);
      for (var i = 1; i < ramp.stages.length; i++) {
        expect(
          ramp.stages[i].fromScore,
          greaterThan(ramp.stages[i - 1].fromScore),
        );
      }
    });

    test('a flat ramp answers the same at every score', () {
      expect(DifficultyRamp.flat.indexFor(0), 0);
      expect(DifficultyRamp.flat.indexFor(999999), 0);
    });
  });

  group('the mix actually widens', () {
    test('equality falls stage by stage and inequality rises', () {
      double equalityShare(DifficultyStage stage) =>
          stage.weights.equalityShareFor(OperatorSet.tier3);

      final shares = [
        for (final stage in DifficultyRamp.endless.stages) equalityShare(stage),
      ];
      for (var i = 1; i < shares.length; i++) {
        expect(
          shares[i],
          lessThan(shares[i - 1]),
          reason: 'stage $i does not widen the mix',
        );
      }
      expect(shares.last, lessThan(0.25), reason: '= should end a minority');
    });

    test('the shipped 4:1:1 gave = two thirds, not four sevenths', () {
      // The bug behind the complaint. `!` is absent from every shipped tier,
      // so the weight table normalised over three glyphs rather than four.
      const defaults = TileWeights();
      expect(
        defaults.equalityShareFor(OperatorSet.tier3),
        closeTo(4 / 6, 0.001),
      );
      expect(
        defaults.equalityShareFor(OperatorSet.tier1),
        1.0,
        reason: 'an equality-only tier is all =, by definition',
      );
    });

    test('applyStage changes what the generator actually draws', () {
      // The share is a claim about the weights; this is the claim about the
      // draw, which is what the player sees.
      final generator = TileGenerator(
        operators: OperatorSet.tier3,
        ids: TileIdGenerator(),
        rng: Random(1),
        stage: DifficultyRamp.endless.stages.first,
      );
      final before = comparisonMix(generator);
      final beforeShare = before['=']! / before.values.reduce((a, b) => a + b);

      generator.applyStage(DifficultyRamp.endless.stages.last);
      final after = comparisonMix(generator);
      final afterShare = after['=']! / after.values.reduce((a, b) => a + b);

      expect(beforeShare, closeTo(0.5, 0.03));
      expect(afterShare, closeTo(0.2, 0.03));
    });

    test('a stage cannot introduce a glyph its tier forbids', () {
      // Tier 1 is equality only. No stage weight may smuggle a `<` in.
      final generator = TileGenerator(
        operators: OperatorSet.tier1,
        ids: TileIdGenerator(),
        rng: Random(3),
        stage: DifficultyRamp.endless.stages.last,
      );
      expect(comparisonMix(generator, draws: 2000).keys, {'='});
    });
  });

  group('the session rides the ramp', () {
    test('endless is on the ramp and the shipped levels are not', () {
      expect(endlessLevel.ramp, same(DifficultyRamp.endless));
      for (final level in levels) {
        expect(
          level.ramp,
          same(DifficultyRamp.flat),
          reason: 'level ${level.id} was tuned against a measured move count',
        );
      }
    });

    test('crossing a threshold moves the generator', () {
      final generator = TileGenerator(
        operators: endlessLevel.operators,
        ids: TileIdGenerator(),
        rng: Random(8),
      );
      final session =
          GameSession(level: endlessLevel, generator: generator);

      expect(session.stageIndex, 0);
      expect(generator.stage.name, 'WARM-UP');

      // Drive the score directly. Reaching 12000 by playing would take a
      // hundred turns and would be measuring the board, not the ramp.
      session.score = 12000;
      session.replenishQueue();
      // replenishQueue does not apply the ramp; a scoring step does.
      final move = session.hint();
      if (move != null) session.trySwap(move.a, move.b);

      expect(session.stageIndex, 3);
      expect(session.stage.name, 'EXPERT');
      expect(generator.stage.name, 'EXPERT');
    });

    test('a deadlock wipe rolls the ramp back to the start', () {
      final generator = TileGenerator(
        operators: endlessLevel.operators,
        ids: TileIdGenerator(),
        rng: Random(8),
      );
      final session =
          GameSession(level: endlessLevel, generator: generator);

      session.score = 9000;
      session.resetAfterDeadlock();

      expect(session.score, 0);
      expect(session.lastRunScore, 9000);
      expect(session.stageIndex, 0, reason: 'the ramp reads the score');
      expect(generator.stage.name, 'WARM-UP');
      expect(
        session.board.obstacleCells(),
        isEmpty,
        reason: 'a fresh board is never dealt obstacles',
      );
    });

    test('a shuffle keeps the score, so it keeps the stage', () {
      final generator = TileGenerator(
        operators: endlessLevel.operators,
        ids: TileIdGenerator(),
        rng: Random(8),
      );
      final session =
          GameSession(level: endlessLevel, generator: generator);

      session.score = 5000;
      session.stageIndex = DifficultyRamp.endless.indexFor(5000);
      session.shuffleBoard();

      expect(session.score, 5000);
      expect(session.stageIndex, 2);
    });

    test('a restored save resumes on the stage its score earned', () {
      final generator = TileGenerator(
        operators: endlessLevel.operators,
        ids: TileIdGenerator(),
        rng: Random(12),
      );
      final original =
          GameSession(level: endlessLevel, generator: generator);
      original.score = 6000;

      final restored = GameSession.fromJson(
        original.toJson(),
        TileGenerator(
          operators: endlessLevel.operators,
          ids: TileIdGenerator(),
          rng: Random(12),
        ),
        endlessLevel,
      );

      expect(restored.score, 6000);
      expect(restored.stageIndex, 2);
      expect(restored.generator.stage.name, 'CROWDED');
    });
  });

  group('the mix correction is bounded and opt-in', () {
    // Two regressions live here, both found by measurement rather than by
    // reading the code, and both silent.

    test('the shipped levels opt out entirely', () {
      // A correction above zero changes what the board is made of, and all
      // twenty levels were tuned against a measured composition. Switching it
      // on for them was measured at 60 points a move becoming 5,500.
      expect(DifficultyStage.warmUp.comparisonCorrection, 0);
      for (final level in levels) {
        for (final stage in level.ramp.stages) {
          expect(
            stage.comparisonCorrection,
            0,
            reason: 'level ${level.id} would have its composition changed',
          );
        }
      }
    });

    test('a stage with no correction draws exactly as the weights say', () {
      final generator = TileGenerator(
        operators: OperatorSet.tier3,
        ids: TileIdGenerator(),
        rng: Random(5),
        stage: DifficultyStage.warmUp,
      );
      // A board wildly short of inequalities must not change the draw at all.
      final starved = {'=': 40, '<': 1, '>': 1};
      final counts = <String, int>{};
      for (var i = 0; i < 20000; i++) {
        final glyph = generator.nextComparisonFor(starved).glyph;
        counts.update(glyph, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(counts['=']! / 20000, closeTo(4 / 6, 0.02));
    });

    test('the correction never saturates, however far off the board is', () {
      // The bug this encodes: a controller chasing a setpoint the board cannot
      // reach will place nothing but the deficient glyph, forever. Since an
      // inequality dropped into a hole completes a true statement about half
      // the time, that turns every refill into a cascade. Whatever the state
      // of the board, every glyph has to keep a real share of the draw.
      final generator = TileGenerator(
        operators: OperatorSet.tier3,
        ids: TileIdGenerator(),
        rng: Random(5),
        stage: DifficultyRamp.endless.stages.last,
      );
      final starved = {'=': 60, '<': 1, '>': 1};
      final counts = <String, int>{};
      for (var i = 0; i < 20000; i++) {
        final glyph = generator.nextComparisonFor(starved).glyph;
        counts.update(glyph, (v) => v + 1, ifAbsent: () => 1);
      }

      for (final glyph in ['=', '<', '>']) {
        expect(
          (counts[glyph] ?? 0) / 20000,
          greaterThan(0.05),
          reason: '$glyph was squeezed out of the draw',
        );
      }
      // ...and it does still correct, or it would not be worth having.
      expect(counts['<']! + counts['>']!, greaterThan(counts['=']!));
    });

    test('the opening board is drawn from the ramp, not from the defaults', () {
      // The board used to be built in the constructor's initialiser list,
      // which runs before the body applies the ramp - so every endless run
      // opened on the legacy equality-heavy mix. Measured at 88% equals on a
      // board whose stage asks for 50%.
      var equals = 0;
      var comparisons = 0;
      for (var seed = 0; seed < 12; seed++) {
        final session = GameSession(
          level: endlessLevel,
          generator: TileGenerator(
            operators: endlessLevel.operators,
            ids: TileIdGenerator(),
            rng: Random(seed),
          ),
        );
        for (final tile in session.board.tiles) {
          if (tile.kind != TileKind.comparison) continue;
          comparisons++;
          if (tile.glyph == '=') equals++;
        }
      }
      expect(comparisons, greaterThan(0));
      expect(
        equals / comparisons,
        lessThan(0.75),
        reason: 'the opening board ignored its own stage weights',
      );
    });
  });

  group('the comparison floor tracks the mix', () {
    test('an equality-heavy board is held to a higher floor', () {
      int floorFor(DifficultyStage stage, OperatorSet operators) =>
          TileGenerator(
            operators: operators,
            ids: TileIdGenerator(),
            rng: Random(0),
            stage: stage,
          ).comparisonFloorFor(8, 8);

      final tier1 = floorFor(DifficultyStage.warmUp, OperatorSet.tier1);
      final tier3 = floorFor(DifficultyStage.warmUp, OperatorSet.tier3);
      final expert =
          floorFor(DifficultyRamp.endless.stages.last, OperatorSet.tier3);

      expect(tier1, greaterThan(tier3),
          reason: 'equality buys fewer moves per glyph');
      expect(expert, lessThan(tier3),
          reason: 'a wide mix needs fewer comparisons to stay alive');
    });

    test('the historical cases land exactly where they used to', () {
      // The old rule was a flat 0.19 of the board, times 1.35 on an
      // equality-only tier. Both must still hold, or twenty tuned levels moved.
      int floorFor(OperatorSet operators) => TileGenerator(
            operators: operators,
            ids: TileIdGenerator(),
            rng: Random(0),
          ).comparisonFloorFor(8, 8);

      expect(floorFor(OperatorSet.tier3), (64 * 0.19).round());
      expect(floorFor(OperatorSet.tier1), (64 * 0.19 * 1.35).round());
    });
  });
}
