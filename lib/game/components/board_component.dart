/// The board: tile components, input, and animation playback.
///
/// The session resolves a whole turn synchronously and hands back an ordered
/// list of [ResolveStep]s. This component replays that list as animation, so it
/// keeps its own mirror of the grid - `_view` - representing what is currently
/// on screen rather than what the model has already settled to.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/material.dart' show Canvas, Paint, RRect, Radius, Rect;

import '../../core/board/board_model.dart';
import '../../core/board/tile.dart';
import '../../core/session/game_session.dart';
import '../../ui/theme/app_theme.dart';
import '../swapper_game.dart';
import 'effects/boom.dart';
import 'effects/feedback_text.dart';
import 'tile_component.dart';
import 'tutorial_hand_component.dart';

/// Fraction of a cell the finger must travel before a drag commits to a swap.
const double _dragThreshold = 0.35;

class BoardComponent extends PositionComponent
    with DragCallbacks, TapCallbacks, HasGameReference<SwapperGame> {
  BoardComponent({required this.session, required this.cellSize})
      : _view = List.generate(
          session.board.height,
          (_) => List<int?>.filled(session.board.width, null),
          growable: false,
        ),
        super(
          size: Vector2(
            session.board.width * cellSize,
            session.board.height * cellSize,
          ),
        );

  final GameSession session;
  final double cellSize;

  /// Tile id currently displayed in each cell. Mirrors the model only when the
  /// board is idle; during playback it lags behind by design.
  final List<List<int?>> _view;

  final Map<int, TileComponent> _components = {};

  /// True while a turn is animating. Input is refused until it clears.
  bool busy = false;

  Coord? _dragFrom;
  Vector2 _dragTravel = Vector2.zero();
  bool _dragCommitted = false;

  Coord? _tapSelection;
  List<Coord> _hintCells = const [];

  int get _width => session.board.width;
  int get _height => session.board.height;

  @override
  Future<void> onLoad() async {
    await _buildFromModel();
  }

  // --- coordinate conversion ---------------------------------------------

  /// Centre of [c] in this component's local pixels.
  Vector2 centerOf(Coord c) =>
      Vector2((c.x + 0.5) * cellSize, (c.y + 0.5) * cellSize);

  /// The cell containing [local], or null if it falls outside the board.
  ///
  /// Floor division, not `~/`: truncation rounds toward zero, so a point just
  /// outside the top-left edge would land in cell (0,0) instead of being
  /// rejected, and a drag started off-board would register as a real tile.
  Coord? cellAt(Vector2 local) {
    final x = (local.x / cellSize).floor();
    final y = (local.y / cellSize).floor();
    if (x < 0 || x >= _width || y < 0 || y >= _height) return null;
    return Coord(x, y);
  }

  // --- construction -------------------------------------------------------

  Future<void> _buildFromModel() async {
    // Remove ALL TileComponents from the Flame tree — including any ghost
    // components that are mid-pop-animation and have already been removed
    // from `_components` but are still rendering. Using removeWhere covers
    // both tracked and untracked (orphaned) tiles in one sweep.
    removeWhere((c) => c is TileComponent);
    _components.clear();

    // One batched add, not sixty-four awaited ones. Each `add` future settles on
    // the next game tick, so awaiting them individually cost a frame per tile.
    final fresh = <TileComponent>[];
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final tile = session.board.at(x, y);
        if (tile == null) continue;
        _view[y][x] = tile.id;
        final component = TileComponent(
          tile: tile,
          position: centerOf(Coord(x, y)),
          cellSize: cellSize,
        );
        _components[tile.id] = component;
        fresh.add(component);
      }
    }
    await addAll(fresh);
  }

  TileComponent? _componentAt(Coord c) {
    final id = _view[c.y][c.x];
    return id == null ? null : _components[id];
  }

  // --- rendering ----------------------------------------------------------

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        Radius.circular(cellSize * 0.22),
      ),
      Paint()..color = AppColors.boardBackground,
    );

    // No grid lines. The blocks are mortared tight, so the dark board showing
    // through the gaps is the grid; drawing lines as well double-strikes every
    // seam and flattens the wall.
    super.render(canvas);
  }

  // --- input --------------------------------------------------------------

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (busy || session.isOver) return;
    _dragFrom = cellAt(event.localPosition);
    _dragTravel = Vector2.zero();
    _dragCommitted = false;
    _clearHint();
    if (_dragFrom != null) _componentAt(_dragFrom!)?.selected = true;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (_dragCommitted || _dragFrom == null || busy) return;

    _dragTravel += event.localDelta;
    if (_dragTravel.length < cellSize * _dragThreshold) return;

    // Commit to whichever axis the finger travelled furthest along, so a sloppy
    // diagonal still resolves to the swap the player meant.
    final horizontal = _dragTravel.x.abs() >= _dragTravel.y.abs();
    final target = horizontal
        ? Coord(_dragFrom!.x + (_dragTravel.x > 0 ? 1 : -1), _dragFrom!.y)
        : Coord(_dragFrom!.x, _dragFrom!.y + (_dragTravel.y > 0 ? 1 : -1));

    _dragCommitted = true;
    final from = _dragFrom!;
    _endDrag();
    if (_inBounds(target)) unawaited(attemptSwap(from, target));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _endDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _endDrag();
  }

  void _endDrag() {
    if (_dragFrom != null) _componentAt(_dragFrom!)?.selected = false;
    _dragFrom = null;
    _dragTravel = Vector2.zero();
  }

  /// Tap-then-tap is the accessible fallback to dragging, and the easier
  /// interaction with a mouse.
  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (busy || session.isOver) return;
    final cell = cellAt(event.localPosition);
    if (cell == null) return;
    _clearHint();

    final selected = _tapSelection;
    if (selected == null) {
      _tapSelection = cell;
      _componentAt(cell)?.selected = true;
      return;
    }

    _componentAt(selected)?.selected = false;
    _tapSelection = null;
    if (selected == cell) return;

    if (selected.isAdjacentTo(cell)) {
      unawaited(attemptSwap(selected, cell));
    } else {
      // Treat a far tap as picking a new tile rather than as a failed swap.
      _tapSelection = cell;
      _componentAt(cell)?.selected = true;
    }
  }

  bool _inBounds(Coord c) =>
      c.x >= 0 && c.x < _width && c.y >= 0 && c.y < _height;

  // --- the turn -----------------------------------------------------------

  /// Runs one player swap and animates whatever it causes.
  Future<void> attemptSwap(Coord a, Coord b) async {
    if (busy || session.isOver) return;
    busy = true;
    try {
      final result = session.trySwap(a, b);

      if (!result.accepted) {
        if (result.rejection == SwapRejection.noMatch || 
            result.rejection == SwapRejection.tutorialLock ||
            result.rejection == SwapRejection.lockedTile) {
          await _animateRejectedSwap(a, b, result.rejection!);
        }
        return;
      }

      game.onSwapAccepted();
      _swapInView(a, b);
      _componentAt(a)?.moveTo(centerOf(a));
      _componentAt(b)?.moveTo(centerOf(b));
      await _sleep(swapDuration);

      for (final step in result.steps) {
        await _playStep(step);
      }

      if (result.boardReset) await _playBoardReset();
      game.onTurnResolved(result);

      // Repair any view/component drift that may have accumulated during the
      // cascade animations. In practice this is a no-op on every healthy turn;
      // it only triggers a rebuild when timing pressure caused a missed update.
      await _reconcileView();
    } finally {
      busy = false;
    }
  }

  Future<void> _animateRejectedSwap(Coord a, Coord b, SwapRejection reason) async {
    _componentAt(a)?.nudgeTo(centerOf(b), returnTo: centerOf(a));
    _componentAt(b)?.nudgeTo(centerOf(a), returnTo: centerOf(b));
    game.onSwapRejected(reason);
    await _sleep(swapDuration * 2);
  }

  void _swapInView(Coord a, Coord b) {
    final tmp = _view[a.y][a.x];
    _view[a.y][a.x] = _view[b.y][b.x];
    _view[b.y][b.x] = tmp;
  }

  Future<void> _playStep(ResolveStep step) async {
    // Pop in reading order so a long equation resolves as a left-to-right wave.
    final cleared = step.cleared.toList()
      ..sort((p, q) => p.y == q.y ? p.x.compareTo(q.x) : p.y.compareTo(q.y));

    if (step.isDischarge) await _playDischarge(step);

    // A power-up takes a whole cross, or every brick of one glyph, at once, so
    // its stagger starts much tighter or the tail of the sweep lags a second
    // behind the flash. Either way the whole wave is held inside
    // [maxClearWindow], so a big cascade step speeds up rather than dragging.
    final baseStagger = step.isDischarge ? clearStagger * 0.25 : clearStagger;
    final stagger = cleared.length < 2
        ? 0.0
        : math.min(baseStagger, maxClearWindow / (cleared.length - 1));

    for (var i = 0; i < cleared.length; i++) {
      final cell = cleared[i];
      final component = _componentAt(cell);
      _view[cell.y][cell.x] = null;
      if (component == null) continue;

      final delay = i * stagger;
      component.popAndRemove(delay: delay);
      _components.remove(component.tile.id);
      unawaited(
        _shatterAfter(delay, cell, component.tile, inBlast: step.isDischarge),
      );
    }

    // Cracked bricks stay on the board, so they are repainted in place rather
    // than removed and rebuilt - the component keeps its identity, and with it
    // any fall it is part of later in this same step.
    for (final entry in step.cracked.entries) {
      // Found by tile id, never by re-reading the cell: the model compacted
      // and refilled the moment the step resolved, so whatever sits at this
      // coordinate now is very probably a different brick.
      final component = _components[entry.value.id];
      if (component == null) continue;
      component.crack(entry.value);
      add(
        crackBurstAt(
          centerOf(entry.key),
          color:
              entry.value.armor >= Armor.diamond ? diamondColor : stoneColor,
          cellSize: cellSize,
        ),
      );
    }

    _showFeedback(step);
    game.onStepResolved(step);
    await _sleep(popDuration + cleared.length * stagger);

    for (final fall in step.falls) {
      final component = _components[fall.tile.id];
      _view[fall.from.y][fall.from.x] = null;
      _view[fall.to.y][fall.to.x] = fall.tile.id;
      component?.fallTo(
        centerOf(fall.to),
        distance: fall.to.y - fall.from.y,
      );
    }

    final freshSpawns = <TileComponent>[];
    final spawnTargets = <TileComponent, TileSpawn>{};

    for (final spawn in step.spawns) {
      _view[spawn.to.y][spawn.to.x] = spawn.tile.id;
      final component = TileComponent(
        tile: spawn.tile,
        position: centerOf(spawn.to) - Vector2(0, spawn.dropDistance * cellSize),
        cellSize: cellSize,
      );
      _components[spawn.tile.id] = component;
      freshSpawns.add(component);
      spawnTargets[component] = spawn;
    }

    if (freshSpawns.isNotEmpty) {
      await addAll(freshSpawns);
      for (final component in freshSpawns) {
        final spawn = spawnTargets[component]!;
        component.fallTo(centerOf(spawn.to), distance: spawn.dropDistance);
      }
    }

    var maxDistance = 0;
    for (final fall in step.falls) {
      final d = fall.to.y - fall.from.y;
      if (d > maxDistance) maxDistance = d;
    }
    for (final spawn in step.spawns) {
      if (spawn.dropDistance > maxDistance) maxDistance = spawn.dropDistance;
    }

    if (step.spawns.isNotEmpty) game.onRefillDropped();
    
    final fallDuration = maxDistance > 0 ? 0.11 + 0.035 * maxDistance : 0.0;
    await _sleep(fallDuration > 0.20 ? fallDuration : 0.20);
  }

  /// Breaks one cell into pieces, timed to land on the peak of its pop.
  ///
  /// A blast clears a whole cross at once. At the per-cell shard count that
  /// suits a five-tile equation, fifteen cells going off together buries the
  /// board in confetti and the explosion stops reading, so a blast gets fewer
  /// shards each and no per-cell ring - the detonation's own shockwave already
  /// carries the sweep.
  Future<void> _shatterAfter(
    double delay,
    Coord cell,
    Tile tile, {
    required bool inBlast,
  }) async {
    await _sleep(delay + popDuration * 0.35);
    if (!isMounted) return;
    final color = tileColor(tile);
    await addAll([
      if (!inBlast)
        shockwaveAt(centerOf(cell), color: color, radius: cellSize * 0.7),
      shatterAt(
        centerOf(cell),
        color: color,
        cellSize: cellSize,
        count: inBlast ? 6 : 12,
      ),
    ]);
  }

  /// The moment a power-up goes off.
  ///
  /// A bomb gets a flare and a shockwave sweeping out along the arms of its
  /// cross. An electric gets an arc to every brick it is about to take, and
  /// those are what the whole feature is for - the sweep has to be legible as
  /// "all of *those*, because of *that* one" before anything starts popping.
  Future<void> _playDischarge(ResolveStep step) async {
    for (final origin in step.detonations) {
      if (!isMounted) return;
      await addAll([
        flashAt(centerOf(origin), radius: cellSize * 1.6),
        shockwaveAt(
          centerOf(origin),
          color: bombColor,
          radius: cellSize * 4.5,
          lifespan: 0.55,
        ),
      ]);
    }

    for (final zap in step.zaps) {
      if (!isMounted) return;
      final from = centerOf(zap.origin);
      // Nearest first, so the sweep reads as spreading outward from the
      // electric rather than arriving in grid order.
      final targets = zap.targets.toList()
        ..sort(
          (p, q) => (from - centerOf(p))
              .length
              .compareTo((from - centerOf(q)).length),
        );

      final arcs = <Component>[
        flashAt(from, radius: cellSize * 1.3, color: electricColor),
      ];
      for (var i = 0; i < targets.length; i++) {
        final delay = i * 0.03;
        arcs
          ..add(
            lightningTo(
              from,
              centerOf(targets[i]),
              color: electricColor,
              startDelay: delay,
            ),
          )
          ..add(
            flashAt(
              centerOf(targets[i]),
              radius: cellSize * 0.5,
              color: electricColor,
              lifespan: 0.20,
              // Lands with its own bolt, not with the first one.
              startDelay: delay,
            ),
          );
      }
      await addAll(arcs);
    }

    game.onDischarge(step);
    // Let the arcs land before the bricks start popping. An electric needs
    // longer than a bomb: its arcs are staggered, and cutting them off halfway
    // loses the causal read.
    await _sleep(step.isZap ? 0.34 : 0.16);
  }

  /// Raises the celebration line and the score popup for a resolved step.
  void _showFeedback(ResolveStep step) {
    // A step that only cracked casings still cleared nothing, and it still
    // scored - anchoring on the cracks is what stops that turn looking like
    // nothing happened.
    final anchors = step.cleared.isNotEmpty
        ? step.cleared
        : step.cracked.keys.toSet();
    if (anchors.isEmpty) return;

    // Anchor the popup on the run itself so the player's eye stays where the
    // action was, rather than being pulled to a fixed HUD corner.
    var sx = 0.0;
    var sy = 0.0;
    for (final cell in anchors) {
      sx += cell.x;
      sy += cell.y;
    }
    final centre = Vector2(
      (sx / anchors.length + 0.5) * cellSize,
      (sy / anchors.length + 0.5) * cellSize,
    );

    add(
      ScorePopupComponent(
        amount: step.score,
        position: centre,
        rise: cellSize * 1.2,
      ),
    );

    final message = step.isDischarge
        ? step.feedback
        : step.cascadeIndex >= 2
            ? 'INCREDIBLE! \u{1F525}'
            : step.feedback;
    if (message.isEmpty) return;

    add(
      FeedbackTextComponent(
        message: message,
        tone: toneFor(message),
        position: Vector2(size.x / 2, size.y * 0.38),
        baseFontSize: cellSize * 0.30,
      ),
    );
  }

  /// Announces the deadlock, clears the board away, and deals the fresh one.
  ///
  /// The pause is deliberately long. The run's score has just been wiped, and
  /// the player needs to read why before a new board appears under them.
  Future<void> _playBoardReset() async {
    // In endless mode, pause here and let the Flutter layer show a
    // "Watch an ad to shuffle?" dialog. The game loop awaits the choice.
    final shouldShuffle = await game.waitForDeadlockChoice();

    if (shouldShuffle) {
      // Player watched the ad: reshuffle without wiping score.
      session.shuffleBoard();
      add(
        FeedbackTextComponent(
          message: 'BOARD SHUFFLED!',
          tone: FeedbackTone.normal,
          position: Vector2(size.x / 2, size.y * 0.38),
          baseFontSize: cellSize * 0.28,
        ),
      );
      await _sleep(0.35);
      for (final component in _components.values) {
        component.add(
          ScaleEffect.to(
            Vector2.zero(),
            EffectController(duration: 0.22, curve: Curves.easeInBack),
          ),
        );
      }
      await _sleep(0.28);
      await _buildFromModel();
    } else {
      // Player declined (or non-endless): normal wipe.
      game.onBoardReset();
      add(
        FeedbackTextComponent(
          message: 'NO MOVES LEFT',
          tone: FeedbackTone.boom,
          position: Vector2(size.x / 2, size.y * 0.38),
          baseFontSize: cellSize * 0.30,
        ),
      );
      await _sleep(0.55);

      for (final component in _components.values) {
        component.add(
          ScaleEffect.to(
            Vector2.zero(),
            EffectController(duration: 0.28, curve: Curves.easeInBack),
          ),
        );
      }
      await _sleep(0.34);
      await _buildFromModel();

      add(
        FeedbackTextComponent(
          message: 'SCORE RESET',
          tone: FeedbackTone.normal,
          position: Vector2(size.x / 2, size.y * 0.38),
          baseFontSize: cellSize * 0.26,
        ),
      );
    }
  }

  /// Drops a saved bomb onto a random ordinary cell and rebuilds the view.
  Future<void> dropBomb() async {
    final targets = <Coord>[];
    for (var y = 0; y < session.board.height; y++) {
      for (var x = 0; x < session.board.width; x++) {
        final coord = Coord(x, y);
        // Never land on another obstacle. Overwriting an electric would spend
        // one power-up to place another, and overwriting a casing would hand
        // back a cell the player was part way through earning.
        if (!(session.board.atCoord(coord)?.isObstacle ?? true)) {
          targets.add(coord);
        }
      }
    }
    if (targets.isEmpty) return;

    final target = targets[session.generator.rng.nextInt(targets.length)];
    session.board.setCoord(target, Tile.bomb(session.generator.ids.nextId()));
    
    // Quick flare effect before rebuilding
    add(
      FeedbackTextComponent(
        message: 'BOMB DEPLOYED!',
        tone: FeedbackTone.boom,
        position: centerOf(target),
        baseFontSize: cellSize * 0.4,
      ),
    );
    await _sleep(0.3);
    await _buildFromModel();
  }

  // --- hint ---------------------------------------------------------------

  TutorialHandComponent? _tutorialHand;

  /// Pulses the tiles of the best available swap.
  void showHint() {
    _clearHint();
    final move = session.hint();
    if (move == null) return;
    _hintCells = [move.a, move.b];
    for (final cell in _hintCells) {
      _componentAt(cell)?.hinting = true;
    }

    if (session.isTutorialActive && _tutorialHand == null) {
      _tutorialHand = TutorialHandComponent(a: move.a, b: move.b);
      add(_tutorialHand!);
    }
  }

  void _clearHint() {
    for (final cell in _hintCells) {
      _componentAt(cell)?.hinting = false;
    }
    _hintCells = const [];

    if (_tutorialHand != null) {
      _tutorialHand?.removeFromParent();
      _tutorialHand = null;
    }
  }

  Future<void> _sleep(double seconds) {
    if (seconds <= 0) return Future.value();
    final completer = Completer<void>();
    add(
      TimerComponent(
        period: seconds,
        onTick: completer.complete,
        removeOnFinish: true,
      ),
    );
    return completer.future;
  }

  // --- test support -------------------------------------------------------

  /// Repairs any cell where the on-screen mirror has drifted from the model.
  ///
  /// After a long cascade chain, animation timing can cause the `_view` or
  /// `_components` map to disagree with `session.board`. This scan detects and
  /// fixes silent drift so orphaned/missing cells can never accumulate over a
  /// long session.
  ///
  /// Called after every resolved turn (when the board is idle). It is cheap:
  /// 64 comparisons against an in-memory map.
  Future<void> _reconcileView() async {
    bool needsRebuild = false;

    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final expected = session.board.at(x, y)?.id;
        final actual = _view[y][x];

        if (expected == actual) {
          // IDs match — verify the component is actually alive.
          if (expected != null) {
            final component = _components[expected];
            if (component == null || !component.isMounted) {
              // Component missing or orphaned — mark for full rebuild.
              needsRebuild = true;
              break;
            } else {
              // Cancel any active movement effects then snap to the exact grid
              // center. Without cancelling, a live MoveToEffect will fight the
              // position write and move the tile back off-grid on the next tick.
              component.removeWhere((c) => c is MoveToEffect || c is MoveEffect);
              component.position = centerOf(Coord(x, y));
            }
          }
        } else {
          // ID mismatch — drift detected.
          needsRebuild = true;
          break;
        }
      }
      if (needsRebuild) break;
    }

    // Check for ghost tiles: components still rendering but not in the tracked
    // map (e.g., mid-pop when their entry was already removed from _components).
    // Count any TileComponent children that aren't in the tracked map.
    if (!needsRebuild) {
      final trackedIds = _components.keys.toSet();
      final hasGhosts = children
          .whereType<TileComponent>()
          .any((c) => !trackedIds.contains(c.tile.id));
      if (hasGhosts || _components.length != _width * _height) {
        needsRebuild = true;
      }
    }

    if (needsRebuild) {
      debugPrint('BoardComponent: view drift detected – rebuilding from model');
      await _buildFromModel();
    }
  }

  /// Rebuilds every component from the model. Test seam, for fixtures that
  /// write tiles straight onto the board.
  @visibleForTesting
  Future<void> rebuildForTest() => _buildFromModel();

  /// Reports any cell where the on-screen mirror disagrees with the model.
  ///
  /// The mirror is the one piece of state here that can silently drift: it is
  /// rebuilt by replaying falls and spawns rather than read from the model, so
  /// a missed step would leave tiles rendering in the wrong cells with nothing
  /// else to catch it. Only meaningful once the board is idle.
  List<String> debugViewDrift() {
    final problems = <String>[];
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final expected = session.board.at(x, y)?.id;
        final actual = _view[y][x];
        if (expected != actual) {
          problems.add('($x,$y): model $expected, view $actual');
          continue;
        }
        if (expected == null) continue;
        final component = _components[expected];
        if (component == null) {
          problems.add('($x,$y): no component for tile $expected');
        } else if (!component.isMounted) {
          problems.add('($x,$y): component for $expected is unmounted');
        }
      }
    }
    if (_components.length != _width * _height) {
      problems.add(
        'component count ${_components.length}, expected ${_width * _height}',
      );
    }
    return problems;
  }
}
