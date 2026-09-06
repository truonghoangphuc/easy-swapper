// Sweeps the tile distribution and reports how many legal moves each setting
// actually produces, per operator tier.
//
// The weights in `lib/core/board/tile_generator.dart` are a hypothesis; this is
// the instrument that settles them. Run it after any change to the weights, the
// matching rules, or the board size:
//
//   dart run tool/tune_weights.dart
//
// Read the `mean` column against a target of roughly 8 to 20 moves on an
// opening board: below that the player hunts too long, above it the board stops
// being a puzzle. `dead%` must stay at zero.

import 'dart:math';

import 'package:easy_swapper/core/board/move_solver.dart';
import 'package:easy_swapper/core/board/tile.dart';
import 'package:easy_swapper/core/board/tile_generator.dart';
import 'package:easy_swapper/core/levels/level_def.dart';
import 'package:easy_swapper/core/session/game_session.dart';

const int samples = 150;
const int boardSize = 8;

void main(List<String> args) {
  if (args.contains('playout')) {
    measurePlayouts();
    return;
  }

  final tiers = {
    'tier1 (+- =)': (OperatorSet.tier1, 3),
    'tier2 (+- =<>)': (OperatorSet.tier2, 3),
    'tier3 (+-*/ =<>)': (OperatorSet.tier3, 3),
    'tier4 (all)': (OperatorSet.tier4, 3),
    'tier2 minRun5': (OperatorSet.tier2, 5),
  };

  // Operators are capped at a third of the board, so the interesting dial is no
  // longer how many there are but how the budget splits. Comparison is the
  // bottleneck - every match consumes exactly one - while + and - are reused
  // across a run, so this sweeps comparison's share of the operator budget.
  const operatorShare = 1 / 3;

  for (final comparisonOfOperators in [0.45, 0.55, 0.65, 0.75, 0.85]) {
    final comparisonShare = operatorShare * comparisonOfOperators;
    final arithmeticShare = operatorShare - comparisonShare;
    final digitShare = 1.0 - operatorShare;

    print('');
    print('comparison ${_pct(comparisonShare)} of operators '
        '${_pct(operatorShare)}  (arithmetic ${_pct(arithmeticShare)}, '
        'digit ${_pct(digitShare)})');
    print('  ${'tier'.padRight(18)} ${'mean'.padLeft(6)} ${'p10'.padLeft(5)} '
        '${'median'.padLeft(7)} ${'max'.padLeft(5)} ${'dead%'.padLeft(6)} '
        '${'ms'.padLeft(5)}');

    tiers.forEach((label, config) {
      final (operators, minRunLength) = config;
      final counts = <int>[];
      var dead = 0;
      final watch = Stopwatch()..start();

      for (var seed = 0; seed < samples; seed++) {
        final gen = TileGenerator(
          operators: operators,
          ids: TileIdGenerator(),
          rng: Random(seed),
          weights: TileWeights(
            digitShare: digitShare,
            arithmeticShare: arithmeticShare,
            comparisonShare: comparisonShare,
          ),
        );
        try {
          final board = gen.generateBoard(
            width: boardSize,
            height: boardSize,
            minRunLength: minRunLength,
            minMoves: 1,
          );
          final moves = findAllLegalMoves(board, minRunLength: minRunLength).length;
          counts.add(moves);
          if (moves == 0) dead++;
        } on BoardGenerationException {
          dead++;
          counts.add(0);
        }
      }
      watch.stop();

      counts.sort();
      final mean = counts.reduce((a, b) => a + b) / counts.length;
      final p10 = counts[(counts.length * 0.10).floor()];
      final median = counts[counts.length ~/ 2];
      final deadPct = dead * 100 / samples;

      print('  ${label.padRight(18)} '
          '${mean.toStringAsFixed(1).padLeft(6)} '
          '${p10.toString().padLeft(5)} '
          '${median.toString().padLeft(7)} '
          '${counts.last.toString().padLeft(5)} '
          '${deadPct.toStringAsFixed(1).padLeft(6)} '
          '${(watch.elapsedMilliseconds / samples).toStringAsFixed(1).padLeft(5)}');
    });
  }
}

String _pct(double v) => '${(v * 100).round()}%'.padLeft(4);

/// Plays random legal moves and reports how long a run survives before the
/// board deadlocks.
///
/// Deadlock now wipes the player's score, so its frequency is a difficulty dial
/// in its own right, not just a robustness check. Run with:
///
///     dart run tool/tune_weights.dart playout
void measurePlayouts() {
  print('');
  print('playout survival (random legal moves until deadlock)');
  print('  ${'tier'.padRight(18)} ${'runs'.padLeft(5)} ${'mean'.padLeft(7)} '
      '${'p10'.padLeft(5)} ${'min'.padLeft(5)} ${'survived'.padLeft(9)}');

  // Bombs matter enormously here: one on the board makes every adjacent swap
  // legal, so it postpones deadlock on its own. Both columns are reported
  // because the no-bomb figure is the true floor of the design.
  final configs = {
    'tier1 (+- =)': (OperatorSet.tier1, 3, 0.0),
    'tier1 +bombs': (OperatorSet.tier1, 3, TileGenerator.defaultBombChance),
    'tier2 (+- =<>)': (OperatorSet.tier2, 3, 0.0),
    'tier2 +bombs': (OperatorSet.tier2, 3, TileGenerator.defaultBombChance),
    'tier3 +bombs': (OperatorSet.tier3, 3, TileGenerator.defaultBombChance),
    'tier2 minRun5': (OperatorSet.tier2, 5, 0.0),
    'tier2 mR5 +bombs': (OperatorSet.tier2, 5, TileGenerator.defaultBombChance),
  };
  const runs = 40;
  const cap = 300;

  print('  (preview: one brick per column)');

  configs.forEach((label, config) {
    final (operators, minRunLength, bombChance) = config;
    final lengths = <int>[];
    var survived = 0;

    for (var seed = 0; seed < runs; seed++) {
      final rng = Random(seed);
      final gen = TileGenerator(
        operators: operators,
        ids: TileIdGenerator(),
        rng: rng,
        bombChance: bombChance,
      );
      final level = LevelDef(
        id: 0,
        moves: -1,
        minRunLength: minRunLength,
        operators: operators,
        objectives: const [],
        starThresholds: const [1, 2, 3],
      );
      final session = GameSession(level: level, generator: gen);

      var moves = 0;
      while (moves < cap) {
        final legal = findAllLegalMoves(
          session.board,
          minRunLength: minRunLength,
        );
        if (legal.isEmpty) break;
        final move = legal[rng.nextInt(legal.length)];
        final result = session.trySwap(move.a, move.b);
        moves++;
        if (result.boardReset) break;
      }
      if (moves >= cap) survived++;
      lengths.add(moves);
    }

    lengths.sort();
    final mean = lengths.reduce((a, b) => a + b) / lengths.length;
    print('  ${label.padRight(18)} ${runs.toString().padLeft(5)} '
        '${mean.toStringAsFixed(1).padLeft(7)} '
        '${lengths[(lengths.length * 0.1).floor()].toString().padLeft(5)} '
        '${lengths.first.toString().padLeft(5)} '
        '${'$survived/$runs'.padLeft(9)}');
  });
}
