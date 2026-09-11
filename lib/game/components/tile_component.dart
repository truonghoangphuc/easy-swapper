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
        Path,
        StrokeCap,
        StrokeJoin,
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

/// Longest the stagger of one clearing step may run, in seconds.
///
/// The stagger is per cell, and nothing bounded it. A cascade step taking
/// twenty-four cells at 0.06s each spends 1.4 seconds just popping, and a
/// chain of eight such steps left one turn animating for thirteen seconds
/// while input sat locked. Big steps now tighten their spacing instead of
/// running long: the wave still reads left to right, it just travels faster
/// the more there is to clear.
const double maxClearWindow = 0.42;

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

  /// Swaps in [next] after an impact took a layer of casing off.
  ///
  /// The brick never leaves the board, so this is a repaint rather than a
  /// rebuild: the block changes colour, the glyph brightens as it comes out
  /// from under the stone, and a flash marks the hit.
  void crack(Tile next) {
    tile = next;
    _base = blockColor(tile);
    _paints = null;
    _flash = 1;
    _syncLabel();
    add(
      SequenceEffect([
        ScaleEffect.to(
          Vector2.all(1.14),
          EffectController(duration: 0.07, curve: Curves.easeOutQuad),
        ),
        ScaleEffect.to(
          Vector2.all(1),
          EffectController(duration: 0.16, curve: Curves.elasticOut),
        ),
      ]),
    );
  }

  /// 0 when idle, 1 at the peak of a clear flash.
  double _flash = 0;

  /// Set while this tile is the one the player has picked up.
  bool selected = false;

  /// Set while the hint is pulsing this tile.
  bool hinting = false;

  double _pulse = 0;

  /// Free-running clock, so a bomb can throb independently of any effect.
  double _clock = 0;

  late Color _base = blockColor(tile);

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

  TextComponent? _label;

  @override
  Future<void> onLoad() async {
    await _syncLabel();
  }

  /// Creates, restyles or removes the glyph label to match [tile].
  ///
  /// A bomb and an electric are drawn, not written. They used to carry emoji,
  /// which depends on the platform having a colour emoji font with that
  /// codepoint - on Windows the bomb came out as a tofu box, and at preview
  /// size it was unreadable. Vector art renders the same everywhere.
  Future<void> _syncLabel() async {
    if (tile.isBomb || tile.isElectric) {
      _label?.removeFromParent();
      _label = null;
      return;
    }

    final style = TextStyle(
      fontFamily: 'Baloo2',
      // The glyph under a casing is dimmed, not hidden. Seeing what is coming
      // is the whole reason an encased brick is worth cracking rather than
      // working around, so it has to stay legible.
      color: glyphColorOn(_base).withValues(alpha: switch (tile.armor) {
        Armor.none => 1.0,
        Armor.stone => 0.5,
        _ => 0.72,
      }),
      fontSize: size.x * 0.50,
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
    );

    final existing = _label;
    if (existing != null) {
      existing.textRenderer = TextPaint(style: style);
      existing.text = tile.glyph;
      return;
    }

    await add(
      _label = TextComponent(
        text: tile.glyph,
        anchor: Anchor.center,
        position: size / 2,
        textRenderer: TextPaint(style: style),
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
    if (tile.isElectric) {
      // Faster and harder than the bomb's slow menace: this one is charged,
      // not fused.
      final throb = 0.5 + 0.5 * math.sin(_clock * 8);
      c = Color.lerp(c, lighten(c, 0.24), throb)!;
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

    if (tile.isBomb) _drawBomb(canvas);
    if (tile.isElectric) _drawElectric(canvas);
    if (tile.isEncased) _drawCasing(canvas);

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

  /// A bomb: a dark sphere with a highlight, a fuse, and a lit tip.
  ///
  /// Proportions are all fractions of the cell, so it reads the same on a board
  /// brick and on a preview brick.
  void _drawBomb(Canvas canvas) {
    final c = size.x;
    final centre = Offset(c * 0.46, c * 0.56);
    final radius = c * 0.21;

    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = const Color(0xFF241A18),
    );
    // Off-centre highlight, lit from the same top-left as the glass.
    canvas.drawCircle(
      Offset(centre.dx - radius * 0.34, centre.dy - radius * 0.38),
      radius * 0.30,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55),
    );

    final fuse = Path()
      ..moveTo(centre.dx + radius * 0.55, centre.dy - radius * 0.80)
      ..quadraticBezierTo(
        c * 0.70,
        c * 0.30,
        c * 0.63,
        c * 0.22,
      );
    canvas.drawPath(
      fuse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c * 0.055
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF3B2A20),
    );

    // The spark, pulsing with the same clock as the body throb.
    final spark = 0.75 + 0.25 * math.sin(_clock * 9);
    canvas.drawCircle(
      Offset(c * 0.63, c * 0.22),
      c * 0.055 * spark,
      Paint()..color = const Color(0xFFFFE082),
    );
    canvas.drawCircle(
      Offset(c * 0.63, c * 0.22),
      c * 0.10 * spark,
      Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.45),
    );
  }

  /// The casing over an encased brick.
  ///
  /// Two looks, told apart by hue and by cut: stone is opaque, angular and
  /// chipped; diamond is translucent with a clean gem facet. They are the same
  /// mechanic at different depths - a diamond that takes a hit becomes a stone
  /// - so reading one as a harder version of the other is exactly right.
  ///
  /// Drawn before `super.render`, which puts it *under* the glyph. The point of
  /// an encased brick is that you can see what is trapped in it.
  void _drawCasing(Canvas canvas) {
    canvas.save();
    canvas.clipRRect(_face);
    if (tile.armor >= Armor.diamond) {
      _drawDiamondFacets(canvas);
    } else {
      _drawStoneChips(canvas);
    }
    canvas.restore();

    // A hard inner line where the casing meets the bevel, so the brick reads
    // as filled rather than merely tinted.
    canvas.drawRRect(
      _face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.x * 0.035
        ..color = (tile.armor >= Armor.diamond
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF3A424E))
            .withValues(alpha: 0.55),
    );
  }

  /// Irregular rock chips, seeded off the tile id.
  ///
  /// Seeded rather than random so a stone brick looks the same on every frame
  /// and every rebuild - a casing that reshuffles itself as the board
  /// compacts reads as a glitch.
  void _drawStoneChips(Canvas canvas) {
    final c = size.x;
    final r = math.Random(tile.id);
    final dark = Paint()..color = const Color(0xFF5A636F).withValues(alpha: 0.55);
    final light = Paint()..color = const Color(0xFFC3CCD8).withValues(alpha: 0.40);

    for (var i = 0; i < 5; i++) {
      final cx = _faceRect.left + r.nextDouble() * _faceRect.width;
      final cy = _faceRect.top + r.nextDouble() * _faceRect.height;
      final radius = c * (0.07 + r.nextDouble() * 0.10);
      final path = Path();
      for (var v = 0; v < 5; v++) {
        final angle = (v / 5) * math.pi * 2 + r.nextDouble() * 0.5;
        final reach = radius * (0.6 + r.nextDouble() * 0.6);
        final px = cx + math.cos(angle) * reach;
        final py = cy + math.sin(angle) * reach;
        v == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      path.close();
      canvas.drawPath(path, i.isEven ? dark : light);
    }
  }

  /// A cut gem: four facets meeting at an off-centre table, plus a bright rim.
  void _drawDiamondFacets(Canvas canvas) {
    final table = Offset(
      _faceRect.center.dx - size.x * 0.04,
      _faceRect.center.dy - size.x * 0.05,
    );
    final corners = [
      _faceRect.topLeft,
      _faceRect.topRight,
      _faceRect.bottomRight,
      _faceRect.bottomLeft,
    ];

    for (var i = 0; i < 4; i++) {
      final path = Path()
        ..moveTo(table.dx, table.dy)
        ..lineTo(corners[i].dx, corners[i].dy)
        ..lineTo(corners[(i + 1) % 4].dx, corners[(i + 1) % 4].dy)
        ..close();
      // Alternate the facets light and dark so the cut catches an edge.
      canvas.drawPath(
        path,
        Paint()
          ..color = (i.isEven
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF3FA8D8))
              .withValues(alpha: i.isEven ? 0.22 : 0.18),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.x * 0.012
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.38),
      );
    }
  }

  /// An electric: a charged core with bolts snapping off it.
  ///
  /// Drawn rather than written, for the same reason the bomb is.
  void _drawElectric(Canvas canvas) {
    final c = size.x;
    final centre = Offset(c * 0.5, c * 0.52);
    final pulse = 0.82 + 0.18 * math.sin(_clock * 11);

    canvas.drawCircle(
      centre,
      c * 0.19 * pulse,
      Paint()..color = const Color(0xFF0C3B5C),
    );
    canvas.drawCircle(
      centre,
      c * 0.13 * pulse,
      Paint()..color = const Color(0xFFE7F8FF).withValues(alpha: 0.92),
    );

    // Six bolts, alternating length, rotating slowly so the tile never sits
    // completely still on the board.
    final bolt = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = c * 0.035
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85);
    for (var i = 0; i < 6; i++) {
      final angle = _clock * 0.9 + (i / 6) * math.pi * 2;
      final inner = c * 0.20;
      final outer = c * (i.isEven ? 0.36 : 0.29) * pulse;
      final mid = (inner + outer) / 2;
      // A kink halfway out is what makes it a bolt rather than a spoke.
      final kink = angle + 0.30;
      canvas.drawPath(
        Path()
          ..moveTo(
            centre.dx + math.cos(angle) * inner,
            centre.dy + math.sin(angle) * inner,
          )
          ..lineTo(
            centre.dx + math.cos(kink) * mid,
            centre.dy + math.sin(kink) * mid,
          )
          ..lineTo(
            centre.dx + math.cos(angle) * outer,
            centre.dy + math.sin(angle) * outer,
          ),
        bolt,
      );
    }
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

  /// Slides to [target] and straight back to [returnTo], for a rejected swap.
  void nudgeTo(Vector2 target, {required Vector2 returnTo}) {
    removeWhere((c) => c is MoveToEffect || c is MoveEffect || c is SequenceEffect);
    add(
      SequenceEffect([
        MoveToEffect(target, EffectController(duration: swapDuration)),
        MoveToEffect(
          returnTo,
          EffectController(duration: swapDuration, curve: Curves.easeOutBack),
        ),
      ]),
    );
  }

  /// Falls to [target], with a distance-scaled duration so a long drop does not
  /// look slower than a short one.
  void fallTo(Vector2 target, {required int distance}) {
    // Cancel any in-progress movement effects so a tile that is still sliding
    // from a previous cascade step snaps cleanly to the new animation rather
    // than fighting with it (which can leave the component off-screen).
    removeWhere((c) => c is MoveToEffect || c is MoveEffect);
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
    // Cancel any ongoing movement first so the pop plays from the correct cell.
    removeWhere((c) => c is MoveToEffect || c is MoveEffect);
    add(
      SequenceEffect([
        ScaleEffect.to(
          Vector2.all(1.22),
          EffectController(startDelay: delay, duration: popDuration * 0.35),
          onComplete: () {
            _flash = 1;
            // Drop the glyph the instant the block breaks. Keeping it while the
            // block shrinks leaves a dark speck riding the shards down.
            _label?.removeFromParent();
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
