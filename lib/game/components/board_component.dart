/// The board: tile components, input, and animation playback.
///
/// The session resolves a whole turn synchronously and hands back an ordered
/// list of [ResolveStep]s. This component replays that list as animation, so it
/// keeps its own mirror of the grid - `_view` - representing what is currently
/// on screen rather than what the model has already settled to.
library;

import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/material.dart' show Canvas, Paint, RRect, Radius, Rect;

import '../../core/board/tile.dart';
import '../../core/session/game_session.dart';
import '../../ui/theme/app_theme.dart';
import '../swapper_game.dart';
import 'effects/boom.dart';
import 'effects/feedback_text.dart';
import 'tile_component.dart';

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
    for (final component in _components.values) {
      component.removeFromParent();
    }
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

  Future<TileComponent> _spawn(Tile tile, Coord at, {Vector2? from}) async {
    final component = TileComponent(
      tile: tile,
      position: from ?? centerOf(at),
      cellSize: cellSize,
    );
    _components[tile.id] = component;
    await add(component);
    return component;
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
        if (result.rejection == SwapRejection.noMatch) {
          await _animateRejectedSwap(a, b);
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
    } finally {
      busy = false;
    }
  }

  Future<void> _animateRejectedSwap(Coord a, Coord b) async {
    _componentAt(a)?.nudgeTo(centerOf(b));
    _componentAt(b)?.nudgeTo(centerOf(a));
    game.onSwapRejected();
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

    if (step.isBlast) await _playDetonation(step);

    // A blast covers a whole row and column at once, so its stagger has to be
    // much tighter or the tail of the cross lags a second behind the flash.
    final stagger = step.isBlast ? clearStagger * 0.25 : clearStagger;

    for (var i = 0; i < cleared.length; i++) {
      final cell = cleared[i];
      final component = _componentAt(cell);
      _view[cell.y][cell.x] = null;
      if (component == null) continue;

      final delay = i * stagger;
      component.popAndRemove(delay: delay);
      _components.remove(component.tile.id);
      unawaited(
        _shatterAfter(delay, cell, component.tile, inBlast: step.isBlast),
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

    for (final spawn in step.spawns) {
      _view[spawn.to.y][spawn.to.x] = spawn.tile.id;
      final component = await _spawn(
        spawn.tile,
        spawn.to,
        from: centerOf(spawn.to) - Vector2(0, spawn.dropDistance * cellSize),
      );
      component.fallTo(centerOf(spawn.to), distance: spawn.dropDistance);
    }

    if (step.spawns.isNotEmpty) game.onRefillDropped();
    await _sleep(0.20);
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

  /// The moment a bomb goes off: a flare at each detonation point and a
  /// shockwave that sweeps out along the arms of the cross.
  Future<void> _playDetonation(ResolveStep step) async {
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
    game.onDetonation(step);
    // Let the flare read before the cross starts clearing.
    await _sleep(0.16);
  }

  /// Raises the celebration line and the score popup for a resolved step.
  void _showFeedback(ResolveStep step) {
    if (step.cleared.isEmpty) return;

    // Anchor the popup on the run itself so the player's eye stays where the
    // action was, rather than being pulled to a fixed HUD corner.
    var sx = 0.0;
    var sy = 0.0;
    for (final cell in step.cleared) {
      sx += cell.x;
      sy += cell.y;
    }
    final centre = Vector2(
      (sx / step.cleared.length + 0.5) * cellSize,
      (sy / step.cleared.length + 0.5) * cellSize,
    );

    add(
      ScorePopupComponent(
        amount: step.score,
        position: centre,
        rise: cellSize * 1.2,
      ),
    );

    final message = step.isBlast
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

  // --- hint ---------------------------------------------------------------

  /// Pulses the tiles of the best available swap.
  void showHint() {
    _clearHint();
    final move = session.hint();
    if (move == null) return;
    _hintCells = [move.a, move.b];
    for (final cell in _hintCells) {
      _componentAt(cell)?.hinting = true;
    }
  }

  void _clearHint() {
    for (final cell in _hintCells) {
      _componentAt(cell)?.hinting = false;
    }
    _hintCells = const [];
  }

  Future<void> _sleep(double seconds) =>
      Future<void>.delayed(Duration(microseconds: (seconds * 1e6).round()));

  // --- test support -------------------------------------------------------

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
