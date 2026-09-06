/// One tile on the board, as a Flame component.
///
/// easy-mathriss drew every cell imperatively inside a single 1354-line
/// `Board.render`. Giving each tile its own component is what makes the
/// animations here declarative: a fall is a [MoveToEffect], a clear is a
/// [ScaleEffect], and neither needs a hand-rolled tween or a frame counter.
///
/// The tile is painted as an architectural glass block rather than a candy: a
/// chunky near-square body, a thick bevelled rim that catches the light, and a
/// translucent core with a specular hotspot top-left and a pool of transmitted
/// light bottom-right. The bevel is what sells it - a flat rounded rectangle
/// with a gradient reads as plastic no matter how the colours are tuned.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/material.dart'
    show
        Alignment,
        Canvas,
        Color,
        FontWeight,
        LinearGradient,
        Offset,
        Paint,
        PaintingStyle,
        RRect,
        RadialGradient,
        Radius,
        Rect,
        Shadow,
        TextStyle;

import '../../core/board/tile.dart';
import '../../ui/theme/app_theme.dart';

/// How long a tile takes to slide one swap.
const double swapDuration = 0.14;

/// How long a cleared tile takes to pop.
const double popDuration = 0.26;

/// Seconds of delay between each tile in a clearing run, so a long equation
/// resolves as a wave rather than all at once. Tuned in easy-mathriss.
const double clearStagger = 0.06;

/// Gap between blocks, as a fraction of the cell. Small: a glass-block wall is
/// mortared tight, and wide gutters make the board read as loose counters.
const double _gapFraction = 0.03;

/// Thickness of the bevelled rim, as a fraction of the cell.
///
/// Kept slim: the bevel is what makes the tile read as a block rather than a
/// counter, but a heavy one turns every cell into a picture frame and the board
/// into a grid of borders.
const double _bevelFraction = 0.075;

/// Every Paint needed to draw one block at one colour.
///
/// Built once per colour and reused. A gradient compiles a shader when it is
/// constructed, and rebuilding nine of them per tile per frame - sixty-four
/// tiles at sixty frames - is the one thing on this canvas that would actually
/// cost frames.
class _BlockPaints {
  _BlockPaints(this.color, Rect outer, Rect face, double s)
      : rim = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lighten(color, 0.18),
              color,
              darken(color, 0.20),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(outer),
        rimHighlight = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.020
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: 0.34),
              const Color(0xFFFFFFFF).withValues(alpha: 0.02),
            ],
            stops: const [0.0, 0.6],
          ).createShader(outer),
        rimEdge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.014
          ..color = darken(color, 0.30).withValues(alpha: 0.50),
        core = Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 1.15,
            colors: [
              lighten(color, 0.16),
              color,
              darken(color, 0.26),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(face),
        caustic = Paint()
          ..shader = RadialGradient(
            center: const Alignment(0.55, 0.7),
            radius: 0.85,
            colors: [
              lighten(color, 0.30).withValues(alpha: 0.42),
              lighten(color, 0.30).withValues(alpha: 0.0),
            ],
          ).createShader(face),
        specular = Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.52, -0.62),
            radius: 0.50,
            colors: [
              const Color(0xFFFFFFFF).withValues(alpha: 0.38),
              const Color(0xFFFFFFFF).withValues(alpha: 0.0),
            ],
          ).createShader(face),
        reed = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.035),
        seam = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.010
          ..color = darken(color, 0.26).withValues(alpha: 0.28),
        lensEdge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.008
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10);

  final Color color;
  final Paint rim;
  final Paint rimHighlight;
  final Paint rimEdge;
  final Paint core;
  final Paint caustic;
  final Paint specular;
  final Paint reed;
  final Paint seam;
  final Paint lensEdge;
}

class TileComponent extends PositionComponent {
  TileComponent({
    required this.tile,
    required super.position,
    required double cellSize,
  }) : super(
          size: Vector2.all(cellSize),
          anchor: Anchor.center,
          priority: 1,
        );

  Tile tile;

  /// 0 when idle, 1 at the peak of a clear flash.
  double _flash = 0;

  /// Set while this tile is the one the player has picked up.
  bool selected = false;

  /// Set while the hint is pulsing this tile.
  bool hinting = false;

  double _pulse = 0;

  /// Free-running clock, so a bomb can throb independently of any effect.
  double _clock = 0;

  late final Color _base = tileColor(tile);

  late final double _gap = size.x * _gapFraction;
  late final Rect _outerRect =
      Rect.fromLTWH(_gap, _gap, size.x - _gap * 2, size.y - _gap * 2);
  late final RRect _outer =
      RRect.fromRectAndRadius(_outerRect, Radius.circular(size.x * 0.11));
  late final Rect _faceRect = _outerRect.deflate(size.x * _bevelFraction);
  late final RRect _face =
      RRect.fromRectAndRadius(_faceRect, Radius.circular(size.x * 0.05));

  late final Paint _shadowNear = Paint()
    ..color = const Color(0xFF000000).withValues(alpha: 0.34);
  late final Paint _shadowFar = Paint()
    ..color = const Color(0xFF000000).withValues(alpha: 0.20);

  _BlockPaints? _paints;

  late final TextComponent _label;

  @override
  Future<void> onLoad() async {
    await add(
      _label = TextComponent(
        text: tile.glyph,
        anchor: Anchor.center,
        position: size / 2,
        textRenderer: TextPaint(
          style: TextStyle(
            color: glyphColorOn(_base),
            fontSize: size.x * (tile.isBomb ? 0.40 : 0.44),
            fontWeight: FontWeight.w800,
            height: 1,
            shadows: [
              // Seats the glyph inside the glass rather than on top of it.
              Shadow(
                color: darken(_base, 0.35).withValues(alpha: 0.7),
                blurRadius: size.x * 0.05,
                offset: Offset(0, size.x * 0.015),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    if (hinting || selected) {
      _pulse += dt * 4;
    } else if (_pulse != 0) {
      _pulse = 0;
    }
  }

  /// The block's colour right now, including the clear flash and the bomb throb.
  Color get _effectiveColor {
    var c = _base;
    if (_flash > 0) {
      // Lightened, not blown to white: a white block with a dark glyph on it
      // reads as a blob rather than as glass catching the light.
      c = Color.lerp(c, lighten(_base, 0.26), _flash)!;
    }
    if (tile.isBomb) {
      final throb = 0.5 + 0.5 * math.sin(_clock * 5);
      c = Color.lerp(c, lighten(c, 0.16), throb)!;
    }
    return c;
  }

  @override
  void render(Canvas canvas) {
    final color = _effectiveColor;
    var paints = _paints;
    if (paints == null || paints.color != color) {
      paints = _paints = _BlockPaints(color, _outerRect, _faceRect, size.x);
    }

    // Two offset silhouettes instead of a blur: a MaskFilter per tile per frame
    // is the most expensive thing on this canvas, and at this size the stacked
    // pair is indistinguishable from a real soft shadow.
    canvas.drawRRect(_outer.shift(Offset(0, size.y * 0.055)), _shadowFar);
    canvas.drawRRect(_outer.shift(Offset(0, size.y * 0.028)), _shadowNear);

    // The bevelled rim, lit from the top left.
    canvas.drawRRect(_outer, paints.rim);

    // The inner face, sunk behind the bevel.
    canvas.drawRRect(_face, paints.core);

    canvas.save();
    canvas.clipRRect(_face);
    _drawReeding(canvas, paints.reed);
    canvas.drawRect(_faceRect, paints.caustic);
    canvas.drawRect(_faceRect, paints.specular);
    canvas.restore();

    // Where the face meets the bevel, then the lens edge catching the light.
    canvas.drawRRect(_face, paints.seam);
    canvas.drawRRect(
      _face.shift(Offset(-size.x * 0.006, -size.x * 0.006)),
      paints.lensEdge,
    );

    canvas.drawRRect(_outer, paints.rimHighlight);
    canvas.drawRRect(_outer, paints.rimEdge);

    _drawSelection(canvas);

    super.render(canvas);
  }

  /// The soft diagonal ribbing cast into real glass block, which is what stops
  /// the core reading as a flat wash of colour.
  void _drawReeding(Canvas canvas, Paint paint) {
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(-0.62);
    final band = size.x * 0.085;
    final length = size.x * 1.5;
    for (var i = -1; i <= 1; i++) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(0, i * size.x * 0.30),
          width: length,
          height: band,
        ),
        paint,
      );
    }
    canvas.restore();
  }

  void _drawSelection(Canvas canvas) {
    if (!selected && !hinting) return;
    // A breathing outline reads better than a static one when the board is
    // busy with falling tiles.
    final glow = 0.55 + 0.45 * math.sin(_pulse);
    final color = selected ? AppColors.selection : AppColors.hint;
    canvas.drawRRect(
      _outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.x * 0.05
        ..color = color.withValues(alpha: glow),
    );
  }

  /// Slides to [target] over [duration].
  void moveTo(Vector2 target, {double duration = swapDuration, Curve? curve}) {
    add(
      MoveToEffect(
        target,
        EffectController(duration: duration, curve: curve ?? Curves.easeOutQuad),
      ),
    );
  }

  /// Slides to [target] and straight back, for a rejected swap.
  void nudgeTo(Vector2 target) {
    final origin = position.clone();
    add(
      SequenceEffect([
        MoveToEffect(target, EffectController(duration: swapDuration)),
        MoveToEffect(
          origin,
          EffectController(duration: swapDuration, curve: Curves.easeOutBack),
        ),
      ]),
    );
  }

  /// Falls to [target], with a distance-scaled duration so a long drop does not
  /// look slower than a short one.
  void fallTo(Vector2 target, {required int distance}) {
    add(
      MoveToEffect(
        target,
        EffectController(
          duration: 0.11 + 0.035 * distance,
          curve: Curves.easeInQuad,
        ),
      ),
    );
  }

  /// Pops and removes itself after [delay] seconds.
  void popAndRemove({double delay = 0}) {
    add(
      SequenceEffect([
        ScaleEffect.to(
          Vector2.all(1.22),
          EffectController(startDelay: delay, duration: popDuration * 0.35),
          onComplete: () {
            _flash = 1;
            // Drop the glyph the instant the block breaks. Keeping it while the
            // block shrinks leaves a dark speck riding the shards down.
            _label.removeFromParent();
          },
        ),
        ScaleEffect.to(
          Vector2.zero(),
          EffectController(duration: popDuration * 0.65, curve: Curves.easeInBack),
        ),
        RemoveEffect(),
      ]),
    );
  }
}
