/// App entry. Deliberately thin: a MaterialApp, a GameWidget, and the overlay
/// wiring. All gameplay lives in `lib/core` and `lib/game`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'core/board/tile_generator.dart';
import 'core/board/tile.dart';
import 'core/levels/level_data.dart';
import 'core/levels/level_def.dart';
import 'core/session/game_session.dart';
import 'game/swapper_game.dart';
import 'services/achievement_service.dart';
import 'services/background_service.dart';
import 'services/progress_service.dart';
import 'services/quest_service.dart';
import 'services/rating_service.dart';
import 'services/save_game_service.dart';
import 'ui/level_select_screen.dart';
import 'ui/overlays/ad_banner.dart';
import 'ui/overlays/deadlock_dialog.dart';
import 'ui/overlays/help_panel.dart';
import 'ui/overlays/hud.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/animated_background.dart';

/// Plays itself, one hinted move at a time. For eyeballing the juice:
///
///     flutter run -d windows --dart-define=autoplay=true
const bool kAutoPlay = bool.fromEnvironment('autoplay');

/// Overrides the bomb spawn rate, as a percentage, so a visual check does not
/// have to wait for one to turn up. Negative means "use the tuned default".
///
///     flutter run -d windows --dart-define=bombpercent=35
const int kBombPercent = int.fromEnvironment('bombpercent', defaultValue: -1);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ProgressService.init();
  await QuestService.init();
  
  final resumeJson = await SaveGameService.load();
  GameSession? resumeSession;
  
  if (resumeJson != null) {
    try {
      final levelId = resumeJson['levelId'] as int;
      final level = levelById(levelId) ?? endlessLevel;
      final generator = TileGenerator(
        operators: level.operators,
        ids: TileIdGenerator(),
        rng: Random(),
        bombChance: kBombPercent < 0 ? TileGenerator.defaultBombChance : kBombPercent / 100,
      );
      resumeSession = GameSession.fromJson(resumeJson, generator, level);
    } catch (e) {
      debugPrint('Failed to parse save game: $e');
    }
  }

  runApp(EasySwapperApp(resumeSession: resumeSession));
}

class EasySwapperApp extends StatelessWidget {
  const EasySwapperApp({super.key, this.resumeSession});

  final GameSession? resumeSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Swapper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: resumeSession != null 
          ? GameScreen(level: resumeSession!.level, session: resumeSession)
          : const LevelSelectScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({required this.level, this.session, super.key});

  final LevelDef level;
  final GameSession? session;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late SwapperGame _game;
  late final BackgroundService _bgService = BackgroundService();

  /// Bumped on restart so the GameWidget rebuilds against a fresh game.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _game = _newGame();
    _game.score.addListener(_onScoreChanged);
    _game.phase.addListener(_onPhaseChanged);
    _game.deadlockPending.addListener(_onDeadlockPending);
    _bgService.addListener(_onBackgroundChanged);
    unawaited(RatingService.incrementSession());
    unawaited(AchievementService.checkVeteran());
  }

  @override
  void dispose() {
    _game.score.removeListener(_onScoreChanged);
    _game.phase.removeListener(_onPhaseChanged);
    _game.deadlockPending.removeListener(_onDeadlockPending);
    _bgService.removeListener(_onBackgroundChanged);
    _bgService.dispose();
    super.dispose();
  }

  void _onScoreChanged() {
    _bgService.onScoreChanged(_game.score.value);
  }

  void _onBackgroundChanged() {
    if (_game.audio.isReady) _game.audio.playBgm(_bgService.index);
    unawaited(AchievementService.checkExplorer(_bgService.index));
  }

  void _onPhaseChanged() {
    // Ask for a rating when the player wins a level or reaches a deadlock
    // (they stayed long enough to care about the game).
    final phase = _game.phase.value;
    if (phase == SessionPhase.won || phase == SessionPhase.lost) {
      unawaited(RatingService.maybeAsk());
    }
  }

  void _onDeadlockPending() {
    if (!_game.deadlockPending.value) return;
    // Show the rewarded-ad dialog over the game. It calls resolveDeadlock()
    // which unblocks the game loop's await.
    if (!mounted) {
      _game.resolveDeadlock(shuffle: false);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeadlockDialog(game: _game),
    );
  }

  SwapperGame _newGame() => SwapperGame(
        level: widget.level,
        session: widget.session,
        autoPlay: kAutoPlay,
        bombChance: kBombPercent < 0 ? null : kBombPercent / 100,
      );

  void _restart() {
    _game.score.removeListener(_onScoreChanged);
    _game.phase.removeListener(_onPhaseChanged);
    _game.deadlockPending.removeListener(_onDeadlockPending);
    _game.audio.stopBgm();
    _bgService.reset();
    setState(() {
      _game = SwapperGame(
        level: widget.level,
        autoPlay: kAutoPlay,
        bombChance: kBombPercent < 0 ? null : kBombPercent / 100,
      );
      _game.score.addListener(_onScoreChanged);
      _game.phase.addListener(_onPhaseChanged);
      _game.deadlockPending.addListener(_onDeadlockPending);
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBackground(
        service: _bgService,
        child: SafeArea(
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
                  Hud(game: _game, onRestart: _restart),
                  Expanded(
                    child: GameWidget<SwapperGame>(
                      key: ValueKey(_generation),
                      game: _game,
                      overlayBuilderMap: {
                        SwapperGame.gameOverOverlay: (_, game) {
                          if (game.session.phase == SessionPhase.won) {
                            ProgressService.saveStars(game.level.id, game.session.stars);
                            ProgressService.unlockNextLevel(game.level.id);
                          }
                          return GameOverPanel(game: game, onRestart: _restart);
                        },
                        SwapperGame.helpOverlay: (_, game) =>
                            HelpPanel(onClose: game.toggleHelp),
                      },
                    ),
                  ),
                  // Below the board, so a banner can never cover a brick or
                  // swallow a drag. Takes no height until an ad actually loads.
                  const AdBanner(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
