/// The in-game heads-up display.
///
/// Every panel listens to a single [ValueNotifier] on the game, so a score tick
/// rebuilds the score chip and nothing else.
library;

import 'package:flutter/material.dart';

import '../../core/levels/level_data.dart';
import '../../core/session/game_session.dart';
import '../../game/swapper_game.dart';
import '../../services/leaderboard_service.dart';
import '../../services/save_game_service.dart';
import '../../main.dart';
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
                if (LeaderboardService.isSupported) ...[
                  const SizedBox(width: 8),
                  _IconChip(
                    icon: Icons.leaderboard_rounded,
                    tooltip: 'Leaderboard',
                    onPressed: LeaderboardService.showLeaderboard,
                    active: false,
                  ),
                ],
                const SizedBox(width: 8),
                _IconChip(
                  icon: Icons.help_outline_rounded,
                  tooltip: 'How to play',
                  onPressed: game.toggleHelp,
                  active: false,
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
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: highlight ? AppColors.danger : AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
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
      builder: (_, on, _) => _IconChip(
        icon: on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        tooltip: on ? 'Mute' : 'Unmute',
        onPressed: game.toggleSound,
        active: on,
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.active,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: 56,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: active ? AppColors.accent : AppColors.textDim),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.boardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.gridLine, width: 1.5),
          ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    // Back to Menu
                    SaveGameService.clear();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.gridLine, width: 2),
                  ),
                  child: const Text('MENU'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onRestart,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.boardBackground,
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.gridLine, width: 2),
                  ),
                  child: const Text('RETRY'),
                ),
                if (won && !game.level.isEndless) ...[
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      SaveGameService.clear();
                      final next = levelById(game.level.id + 1);
                      if (next != null) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => GameScreen(level: next)),
                        );
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                    ),
                    child: const Text('NEXT'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
