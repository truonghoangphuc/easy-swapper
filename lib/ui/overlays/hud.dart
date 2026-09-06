/// The in-game heads-up display.
///
/// Every panel listens to a single [ValueNotifier] on the game, so a score tick
/// rebuilds the score chip and nothing else.
library;

import 'package:flutter/material.dart';

import '../../core/session/game_session.dart';
import '../../game/swapper_game.dart';
import '../theme/app_theme.dart';

class Hud extends StatelessWidget {
  const Hud({required this.game, super.key});

  final SwapperGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: game.score,
                    builder: (_, score, _) =>
                        _Chip(label: 'SCORE', value: '$score'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: game.movesRemaining,
                    builder: (_, moves, _) => _Chip(
                      label: game.level.isEndless ? 'MODE' : 'MOVES',
                      value: game.level.isEndless ? 'ENDLESS' : '$moves',
                      highlight: !game.level.isEndless && moves <= 5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SoundToggle(game: game),
              ],
            ),
            if (game.level.objectives.isNotEmpty) ...[
              const SizedBox(height: 8),
              _Objectives(game: game),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.boardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppColors.danger : AppColors.gridLine,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppColors.danger : AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundToggle extends StatelessWidget {
  const _SoundToggle({required this.game});

  final SwapperGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: game.soundOn,
      builder: (_, on, _) => IconButton(
        onPressed: game.toggleSound,
        tooltip: on ? 'Mute' : 'Unmute',
        icon: Icon(
          on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: on ? AppColors.accent : AppColors.textDim,
        ),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.boardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.gridLine, width: 1.5),
          ),
          padding: const EdgeInsets.all(14),
        ),
      ),
    );
  }
}

class _Objectives extends StatelessWidget {
  const _Objectives({required this.game});

  final SwapperGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<double>>(
      valueListenable: game.objectiveProgress,
      builder: (_, progress, _) {
        return Column(
          children: [
            for (var i = 0; i < game.level.objectives.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        game.level.objectives[i].label,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: i < progress.length ? progress[i] : 0,
                          minHeight: 6,
                          backgroundColor: AppColors.gridLine,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shown when the session ends, win or lose.
class GameOverPanel extends StatelessWidget {
  const GameOverPanel({required this.game, required this.onRestart, super.key});

  final SwapperGame game;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final won = game.session.phase == SessionPhase.won;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.boardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: won ? AppColors.accent : AppColors.danger,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              won ? 'LEVEL CLEAR' : 'OUT OF MOVES',
              style: TextStyle(
                color: won ? AppColors.accent : AppColors.danger,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${game.session.score} points',
              style: const TextStyle(color: AppColors.text, fontSize: 18),
            ),
            if (!game.level.isEndless) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(
                      i < game.session.stars ? Icons.star : Icons.star_border,
                      color: AppColors.gold,
                      size: 34,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRestart,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
              ),
              child: const Text('PLAY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }
}
