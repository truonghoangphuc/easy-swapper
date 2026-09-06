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
    show Color, Offset, Paint, PaintingStyle, RRect, Radius, Rect;

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
        canvas.drawCircle(
          Offset.zero,
          radius * (0.15 + t * 0.85),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.14 * (1 - t)
            ..color = color.withValues(alpha: (1 - t) * 0.8),
        );
      },
    ),
  );
}

/// A brief white flare, used at the centre of a bomb blast.
ParticleSystemComponent flashAt(
  Vector2 position, {
  required double radius,
  Color color = const Color(0xFFFFFFFF),
  double lifespan = 0.28,
}) {
  return ParticleSystemComponent(
    position: position,
    priority: 7,
    particle: ComputedParticle(
      lifespan: lifespan,
      renderer: (canvas, particle) {
        final fade = 1 - particle.progress;
        canvas.drawCircle(
          Offset.zero,
          radius * (0.4 + particle.progress * 0.6),
          Paint()..color = color.withValues(alpha: fade * 0.85),
        );
      },
    ),
  );
}
