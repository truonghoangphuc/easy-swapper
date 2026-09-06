/// The Flame game: camera, world, and the bridge to the Flutter overlays.
///
/// State reaches the UI through [ValueNotifier]s rather than the single
/// `onStateChanged` mega-callback easy-mathriss used, so an overlay can rebuild
/// on just the value it cares about instead of the whole screen rebuilding on
/// every score tick.
library;

import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../core/board/tile.dart';
import '../core/board/tile_generator.dart';
import '../core/levels/level_def.dart';
import '../core/session/game_session.dart';
import '../services/ad_service.dart';
import '../services/leaderboard_service.dart';
import '../ui/theme/app_theme.dart';
import 'audio/audio_manager.dart';
import 'components/board_component.dart';
import 'components/preview_component.dart';

/// Pixel size of one cell in world space. The camera scales this to the device.
const double cellSize = 100;

/// Margin around the board, in world pixels.
const double boardMargin = 24;

/// Vertical space the next-drop strip occupies: the caption plus a full-size
/// brick row, since a preview brick is the same size as the brick that lands.
const double previewBandHeight = cellSize + 34;

/// Gap between the preview strip and the board.
///
/// Generous on purpose: the preview bricks are the same size as board bricks,
/// so a tight gap makes the strip read as a ninth row of play rather than as
/// tiles waiting to enter.
const double previewGap = 34;

/// Seconds of inactivity before the hint pulses.
const double hintDelay = 6;

/// Seconds between moves when [SwapperGame.autoPlay] is on.
const double autoPlayInterval = 0.6;

class SwapperGame extends FlameGame {
  /// The one Flame overlay left. The HUD is a plain sibling widget of the
  /// GameWidget rather than an overlay, because as an overlay it painted over
  /// the top row of the board.
  static const String gameOverOverlay = 'gameOver';

  /// The rules screen, opened from the HUD.
  static const String helpOverlay = 'help';

  bool get helpVisible => overlays.isActive(helpOverlay);

  void toggleHelp() {
    if (helpVisible) {
      overlays.remove(helpOverlay);
    } else {
      overlays.add(helpOverlay);
    }
  }

  SwapperGame({
    required this.level,
    int? seed,
    this.autoPlay = false,
    double? bombChance,
  }) : session = GameSession(
          level: level,
          generator: TileGenerator(
            operators: level.operators,
            ids: TileIdGenerator(),
            rng: seed == null ? Random() : Random(seed),
            bombChance: bombChance ?? TileGenerator.defaultBombChance,
          ),
        );

  final LevelDef level;
  final GameSession session;

  final AudioManager audio = AudioManager();

  /// Plays hinted moves on a timer instead of waiting for input. A development
  /// aid for eyeballing the effects, never on in a normal run.
  final bool autoPlay;

  late final BoardComponent board;
  late final PreviewComponent preview;

  // --- state the overlays listen to ---
  final score = ValueNotifier<int>(0);
  final movesRemaining = ValueNotifier<int>(0);
  final phase = ValueNotifier<SessionPhase>(SessionPhase.idle);

  /// Last celebration line, and a counter so the HUD can retrigger its
  /// animation even when the same text comes up twice.
  final feedback = ValueNotifier<(String, int)>(('', 0));

  /// Objective progress, one fraction per objective, in level order.
  final objectiveProgress = ValueNotifier<List<double>>(const []);

  /// Mirrors [AudioManager.soundEnabled] so the HUD can render the mute button.
  final soundOn = ValueNotifier<bool>(true);

  int _feedbackTicks = 0;
  double _idleFor = 0;

  @override
  Color backgroundColor() => AppColors.background;

  @override
  Future<void> onLoad() async {
    final boardWidth = level.width * cellSize;
    final boardHeight = level.height * cellSize;
    final boardTop = boardMargin + previewBandHeight + previewGap;

    // Column-aligned with the board and the same brick size, so a brick in the
    // strip is visibly the brick that will land in the column beneath it.
    preview = PreviewComponent(
      queue: session.queue,
      cellSize: cellSize,
      position: Vector2(boardMargin, boardMargin + 34),
    );

    board = BoardComponent(session: session, cellSize: cellSize);

    // The board is clipped to its own bounds. Refilled tiles start a row above
    // the top edge and fall in, and that row now sits inside the preview band -
    // without a clip they visibly fly through the strip on their way down.
    final clip = ClipComponent.rectangle(
      position: Vector2(boardMargin, boardTop),
      size: Vector2(boardWidth, boardHeight),
    );
    await clip.add(board);

    await world.addAll([
      preview,
      PreviewLabel(
        cellSize: cellSize,
        position: Vector2(boardMargin, boardMargin + 15),
      ),
      clip,
    ]);

    final worldHeight = boardTop + boardHeight + boardMargin;
    camera = CameraComponent.withFixedResolution(
      world: world,
      width: boardWidth + boardMargin * 2,
      height: worldHeight,
    )..viewfinder.position = Vector2(
        boardWidth / 2 + boardMargin,
        worldHeight / 2,
      );

    _publish();

    // Audio, ads and leaderboards all load in the background. None of them is
    // allowed to hold up the first frame, and none of them failing is allowed
    // to stop the game: a missing clip costs silence, a missing fill costs an
    // empty banner slot, a declined sign-in costs a leaderboard.
    unawaited(_initAudio());
    unawaited(AdService.init());
    unawaited(LeaderboardService.signIn());
  }

  Future<void> _initAudio() async {
    await audio.init();
    soundOn.value = audio.soundEnabled;
  }

  /// Flips mute, persisting the choice.
  Future<void> toggleSound() async {
    soundOn.value = await audio.toggleSound();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (board.busy || session.isOver || helpVisible) {
      _idleFor = 0;
      return;
    }
    _idleFor += dt;

    if (autoPlay) {
      if (_idleFor >= autoPlayInterval) {
        _idleFor = 0;
        final move = session.hint();
        if (move != null) unawaited(board.attemptSwap(move.a, move.b));
      }
      return;
    }

    if (_idleFor >= hintDelay) {
      _idleFor = 0;
      board.showHint();
    }
  }

  // --- callbacks from the board -------------------------------------------

  /// The player's swap was accepted and the tiles are sliding.
  void onSwapAccepted() => audio.play(Sfx.swap);

  /// A step of a cascade finished resolving.
  ///
  /// The celebration line is drawn on the board itself by
  /// `FeedbackTextComponent`. The notifier stays so the HUD can still react to
  /// it, but the words no longer live in a corner of the screen.
  void onStepResolved(ResolveStep step) {
    score.value = session.score;
    if (step.feedback.isNotEmpty) _say(step.feedback);

    // One clip per step, never one per cell: a fifteen-cell blast firing
    // fifteen overlapping clears is noise, not feedback.
    if (!step.isBlast) {
      audio.play(
        step.cascadeIndex >= 2 ? Sfx.boom : Sfx.clear,
        // Each link of a cascade lands a little louder than the last.
        volume: 0.45 + 0.08 * step.cascadeIndex.clamp(0, 3),
      );
    }
  }

  /// Refilled tiles have started falling.
  void onRefillDropped() => audio.play(Sfx.drop, volume: 0.25);

  /// A whole turn finished, board settled.
  void onTurnResolved(SwapResult result) {
    _idleFor = 0;
    unawaited(preview.sync());
    _publish();
  }

  void onSwapRejected() {
    _idleFor = 0;
    audio.play(Sfx.reject, volume: 0.35);
  }

  /// A bomb went off. Kept separate from [onStepResolved] so audio and haptics
  /// can fire on the flare rather than on the score.
  void onDetonation(ResolveStep step) {
    _idleFor = 0;
    audio.play(Sfx.boom, volume: 0.7);
  }

  /// The board deadlocked: the run was wiped and a new board dealt.
  void onBoardReset() {
    _idleFor = 0;
    unawaited(preview.sync());
    audio.play(Sfx.gameOver, volume: 0.6);
    _say('NO MOVES LEFT');
    // The run is over even though play continues, so this is where its score
    // goes to the leaderboard.
    unawaited(LeaderboardService.submitScore(session.lastRunScore));
    _publish();
  }

  void _say(String message) {
    feedback.value = (message, ++_feedbackTicks);
  }

  void _publish() {
    score.value = session.score;
    movesRemaining.value = session.movesRemaining;
    phase.value = session.phase;
    objectiveProgress.value = [
      for (final objective in level.objectives) session.progressOn(objective),
    ];

    if (session.isOver) {
      unawaited(LeaderboardService.submitScore(session.score));
      overlays.add(gameOverOverlay);
    } else {
      overlays.remove(gameOverOverlay);
    }
  }

  @override
  void onRemove() {
    score.dispose();
    movesRemaining.dispose();
    phase.dispose();
    feedback.dispose();
    objectiveProgress.dispose();
    soundOn.dispose();
    unawaited(audio.dispose());
    super.onRemove();
  }
}
