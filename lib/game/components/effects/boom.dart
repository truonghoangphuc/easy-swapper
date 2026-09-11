/// What a resolved cell leaves behind: shards, a shockwave, and a flash.
///
/// Uses Flame's particle system rather than the hand-rolled `CellParticle` loop
/// easy-mathriss carried, so each burst removes itself when it finishes.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/material.dart'
    show
        Color,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        RRect,
        Radius,
        Rect,
        StrokeCap,
        StrokeJoin;

import '../../../ui/theme/app_theme.dart';

final math.Random _rng = math.Random();

/// The tile breaking apart into pieces.
///
/// Shards are drawn as small rounded rectangles in the tile's own colour rather
/// than as dots, so the eye reads them as fragments of the cell that was there
/// a moment ago. Each spins on its own axis and is pulled down, which turns a
/// symmetrical burst into debris.
ParticleSystemComponent shatterAt(
  Vector2 position, {
  required Color color,
  required double cellSize,
  int count = 14,
}) {
  return ParticleSystemComponent(
    position: position,
    priority: 6,
    particle: Particle.generate(
      count: count,
      lifespan: 0.7,
      generator: (_) {
        final angle = _rng.nextDouble() * math.pi * 2;
        final speed = cellSize * (1.2 + _rng.nextDouble() * 2.8);
        final w = cellSize * (0.11 + _rng.nextDouble() * 0.16);
        final h = w * (0.55 + _rng.nextDouble() * 0.8);
        final spin = (_rng.nextDouble() - 0.5) * 14;
        final startAngle = _rng.nextDouble() * math.pi;
        // Vary the shade so the pieces do not look stamped from one template.
        final shade = _rng.nextBool()
            ? lighten(color, 0.12 * _rng.nextDouble())
            : darken(color, 0.14 * _rng.nextDouble());

        return AcceleratedParticle(
          speed: Vector2(math.cos(angle), math.sin(angle)) * speed
            ..y -= cellSize * 1.5,
          acceleration: Vector2(0, cellSize * 5.0),
          child: ComputedParticle(
            renderer: (canvas, particle) {
              final t = particle.progress;
              final fade = (1 - t * t).clamp(0.0, 1.0);
              canvas.save();
              canvas.rotate(startAngle + spin * t);
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(
                    center: Offset.zero,
                    width: w * (1 - t * 0.35),
                    height: h * (1 - t * 0.35),
                  ),
                  Radius.circular(w * 0.3),
                ),
                Paint()..color = shade.withValues(alpha: fade),
              );
              canvas.restore();
            },
          ),
        );
      },
    ),
  );
}

/// A single expanding ring, for the moment of impact.
ParticleSystemComponent shockwaveAt(
  Vector2 position, {
  required Color color,
  required double radius,
  double lifespan = 0.4,
}) {
  return ParticleSystemComponent(
    position: position,
    priority: 5,
    particle: ComputedParticle(
      lifespan: lifespan,
      renderer: (canvas, particle) {
        final t = Curves.easeOutQuad.transform(particle.progress);
        final fade = 1 - t;
        
        // Outer high-pressure ring
        canvas.drawCircle(
          Offset.zero,
          radius * (0.15 + t * 0.85),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.14 * fade
            ..color = color.withValues(alpha: fade * 0.9),
        );
        
        // Inner trailing ring
        canvas.drawCircle(
          Offset.zero,
          radius * (0.05 + t * 0.65),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.25 * fade
            ..color = color.withValues(alpha: fade * 0.5),
        );
        
        // Core concussive flash
        canvas.drawCircle(
          Offset.zero,
          radius * (0.1 + t * 0.95),
          Paint()
            ..style = PaintingStyle.fill
            ..color = color.withValues(alpha: fade * 0.25),
        );
      },
    ),
  );
}

/// A brief white flare, used at the centre of a bomb blast.
///
/// [startDelay] holds the flare dark until it is due. Without it a staggered
/// sweep lights every target at once while its bolts are still travelling, and
/// the effect stops reading as one thing causing another - which is the only
/// reason to draw the bolts at all.
ParticleSystemComponent flashAt(
  Vector2 position, {
  required double radius,
  Color color = const Color(0xFFFFFFFF),
  double lifespan = 0.28,
  double startDelay = 0,
}) {
  return ParticleSystemComponent(
    position: position,
    priority: 7,
    particle: ComputedParticle(
      lifespan: lifespan + startDelay,
      renderer: (canvas, particle) {
        final elapsed = particle.progress * (lifespan + startDelay);
        if (elapsed < startDelay) return;

        final t = ((elapsed - startDelay) / lifespan).clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset.zero,
          radius * (0.4 + t * 0.6),
          Paint()..color = color.withValues(alpha: (1 - t) * 0.85),
        );
      },
    ),
  );
}

/// A lightning arc from one cell to another, for an electric discharge.
///
/// The jitter is regenerated on **every frame** rather than once at
/// construction, which is what makes the bolt crackle instead of sitting there
/// as a static zig-zag. It is a dozen points of trigonometry per arc per
/// frame over a third of a second - cheap next to the shard bursts that follow
/// it.
///
/// Two strokes: a wide translucent glow in [color] underneath a thin white
/// core. That pairing is what reads as "hot" at any size; a single stroke of
/// either one alone reads as a drawn line.
ParticleSystemComponent lightningTo(
  Vector2 from,
  Vector2 to, {
  required Color color,
  double lifespan = 0.30,
  double startDelay = 0,
}) {
  final delta = to - from;
  final length = delta.length;
  // Perpendicular unit vector: the axis the bolt wanders along.
  final nx = length == 0 ? 0.0 : -delta.y / length;
  final ny = length == 0 ? 0.0 : delta.x / length;
  const segments = 7;
  final spread = length * 0.07;

  return ParticleSystemComponent(
    position: from,
    priority: 8,
    particle: ComputedParticle(
      lifespan: lifespan + startDelay,
      renderer: (canvas, particle) {
        // Hold off until the stagger has elapsed, so a sweep reads as a
        // sequence of strikes rather than one simultaneous flash.
        final elapsed = particle.progress * (lifespan + startDelay);
        if (elapsed < startDelay) return;

        final t = ((elapsed - startDelay) / lifespan).clamp(0.0, 1.0);
        // Snaps to full brightness, then decays - the shape of a real spark.
        final fade = (1 - t) * (1 - t);

        final path = Path()..moveTo(0, 0);
        for (var i = 1; i < segments; i++) {
          final f = i / segments;
          final wander = (_rng.nextDouble() - 0.5) * 2 * spread;
          path.lineTo(
            delta.x * f + nx * wander,
            delta.y * f + ny * wander,
          );
        }
        path.lineTo(delta.x, delta.y);

        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9 * fade
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = color.withValues(alpha: fade * 0.55),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * fade
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFFFFFFF).withValues(alpha: fade * 0.95),
        );
      },
    ),
  );
}

/// The chips that fly off a casing taking a hit.
///
/// Deliberately unlike [shatterAt]: fewer pieces, smaller, heavier, and thrown
/// sideways rather than up. A cracked brick is still there, so the burst must
/// not read as the cell being destroyed.
ParticleSystemComponent crackBurstAt(
  Vector2 position, {
  required Color color,
  required double cellSize,
  int count = 7,
}) {
  return ParticleSystemComponent(
    position: position,
    priority: 6,
    particle: Particle.generate(
      count: count,
      lifespan: 0.45,
      generator: (_) {
        final angle = _rng.nextDouble() * math.pi * 2;
        final speed = cellSize * (0.8 + _rng.nextDouble() * 1.4);
        final w = cellSize * (0.06 + _rng.nextDouble() * 0.07);
        final spin = (_rng.nextDouble() - 0.5) * 10;

        return AcceleratedParticle(
          speed: Vector2(math.cos(angle), math.sin(angle)) * speed,
          acceleration: Vector2(0, cellSize * 7.0),
          child: ComputedParticle(
            renderer: (canvas, particle) {
              final t = particle.progress;
              canvas.save();
              canvas.rotate(spin * t);
              canvas.drawRect(
                Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.7),
                Paint()
                  ..color = darken(color, 0.10)
                      .withValues(alpha: (1 - t).clamp(0.0, 1.0)),
              );
              canvas.restore();
            },
          ),
        );
      },
    ),
  );
}
