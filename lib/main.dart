/// App entry. Deliberately thin: a MaterialApp, a GameWidget, and the overlay
/// wiring. All gameplay lives in `lib/core` and `lib/game`.
library;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'core/levels/level_data.dart';
import 'core/levels/level_def.dart';
import 'game/swapper_game.dart';
import 'ui/overlays/hud.dart';
import 'ui/theme/app_theme.dart';

/// Plays itself, one hinted move at a time. For eyeballing the juice:
///
///     flutter run -d windows --dart-define=autoplay=true
const bool kAutoPlay = bool.fromEnvironment('autoplay');

/// Overrides the bomb spawn rate, as a percentage, so a visual check does not
/// have to wait for one to turn up. Negative means "use the tuned default".
///
///     flutter run -d windows --dart-define=bombpercent=35
const int kBombPercent = int.fromEnvironment('bombpercent', defaultValue: -1);

void main() {
  runApp(const EasySwapperApp());
}

class EasySwapperApp extends StatelessWidget {
  const EasySwapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Swapper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const GameScreen(level: endlessLevel),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({required this.level, super.key});

  final LevelDef level;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late SwapperGame _game;

  /// Bumped on restart so the GameWidget rebuilds against a fresh game.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _game = _newGame();
  }

  SwapperGame _newGame() => SwapperGame(
        level: widget.level,
        autoPlay: kAutoPlay,
        bombChance: kBombPercent < 0 ? null : kBombPercent / 100,
      );

  void _restart() {
    setState(() {
      _game = _newGame();
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          // The board is square, so on a wide window it is letterboxed rather
          // than stretched. easy-mathriss does the same for its 9:16 field.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 1000),
            child: Column(
              children: [
                // The HUD is a sibling of the board, not an overlay on top of
                // it. As an overlay it covered the top row, and no amount of
                // padding fixes that reliably once the camera starts scaling.
                Hud(game: _game),
                Expanded(
                  child: GameWidget<SwapperGame>(
                    key: ValueKey(_generation),
                    game: _game,
                    overlayBuilderMap: {
                      SwapperGame.gameOverOverlay: (_, game) =>
                          GameOverPanel(game: game, onRestart: _restart),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
