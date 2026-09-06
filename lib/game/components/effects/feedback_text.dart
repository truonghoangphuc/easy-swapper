/// Floating celebration text and score popups, drawn on the board.
///
/// Ported from the feedback block in
/// `easy-mathriss/lib/game/components/board.dart`: an elastic spring entry, a
/// decaying sway, and three stacked text layers - a black silhouette, an
/// offset colour silhouette, then the bright face - which is what gives the
/// words their poster-like weight instead of looking like a debug label.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/material.dart'
    show Color, Colors, FontWeight, Offset, Shadow, TextAlign, TextPainter,
        TextSpan, TextStyle;

import '../../../ui/theme/app_theme.dart';

/// The celebration face, matching easy-mathriss.
///
/// Sour Gummy is a rounded display face, bundled with the app rather than
/// fetched, so it is there on the first frame and works offline.
TextStyle feedbackStyle({
  required double fontSize,
  required FontWeight weight,
  Color? color,
}) =>
    TextStyle(
      fontFamily: 'SourGummy',
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      height: 1.2,
      letterSpacing: 2,
    );

/// How loud a feedback line is.
enum FeedbackTone {
  /// Ordinary clear: GOOD JOB, EXCELLENT.
  normal,

  /// A deep cascade.
  incredible,

  /// A bomb went off.
  boom,
}

/// Picks the tone implied by [message], matching easy-mathriss's keyword test.
FeedbackTone toneFor(String message) {
  if (message.contains('INCREDIBLE')) return FeedbackTone.incredible;
  if (message.contains('BOOM')) return FeedbackTone.boom;
  return FeedbackTone.normal;
}

/// A line of celebration text that springs in, sways, and fades.
class FeedbackTextComponent extends PositionComponent {
  FeedbackTextComponent({
    required this.message,
    required this.tone,
    required super.position,
    this.baseFontSize = 30,
  }) : super(priority: 20, anchor: Anchor.center);

  final String message;
  final FeedbackTone tone;
  final double baseFontSize;

  double _elapsed = 0;

  double get _duration => tone == FeedbackTone.normal ? 1.5 : 1.8;

  late final ({Color primary, Color secondary}) _palette = switch (tone) {
    FeedbackTone.incredible => (
        primary: const Color(0xFFFF6D00),
        secondary: const Color(0xFFFFD600),
      ),
    FeedbackTone.boom => (
        primary: const Color(0xFFFF3D00),
        secondary: AppColors.gold,
      ),
    FeedbackTone.normal => (
        primary: Colors.cyanAccent,
        secondary: Colors.blueAccent,
      ),
  };

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) removeFromParent();
  }

  @override
  void render(ui.Canvas canvas) {
    final progress = (_elapsed / _duration).clamp(0.0, 1.0);
    final big = tone != FeedbackTone.normal;

    final scale = big
        ? 0.4 + 1.1 * Curves.elasticOut.transform((progress * 1.2).clamp(0.0, 1.0))
        : 0.5 + 0.8 * Curves.elasticOut.transform(progress);

    // The sway decays as the line settles, so it reads as momentum rather than
    // a loop. Incredible wiggles faster.
    final rotation = tone == FeedbackTone.incredible
        ? 0.30 * (1 - progress) * math.sin(progress * 12 * math.pi)
        : 0.22 * (1 - progress) * math.sin(progress * 8 * math.pi);

    final opacity =
        progress < 0.75 ? 1.0 : (1 - (progress - 0.75) / 0.25).clamp(0.0, 1.0);

    final style = feedbackStyle(
      fontSize: big ? baseFontSize * 1.15 : baseFontSize,
      weight: FontWeight.w700,
    );

    canvas.save();
    canvas.scale(scale);
    canvas.rotate(rotation);

    _layer(canvas, style, Colors.black.withValues(alpha: 0.5 * opacity), 6);
    _layer(canvas, style, _palette.secondary.withValues(alpha: 0.85 * opacity), 3);

    final face = TextPainter(
      text: TextSpan(
        text: message,
        style: style.copyWith(
          color: _palette.primary.withValues(alpha: opacity),
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: opacity),
              blurRadius: 4,
            ),
            if (big)
              Shadow(
                color: _palette.secondary.withValues(alpha: opacity * 0.7),
                blurRadius: 18,
              ),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    face.paint(canvas, Offset(-face.width / 2, -face.height / 2));

    canvas.restore();
  }

  void _layer(ui.Canvas canvas, TextStyle style, Color color, double offset) {
    final painter = TextPainter(
      text: TextSpan(text: message, style: style.copyWith(color: color)),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(-painter.width / 2 + offset, -painter.height / 2 + offset),
    );
  }
}

/// A `+42` that rises out of a resolved run and fades.
class ScorePopupComponent extends PositionComponent {
  ScorePopupComponent({
    required this.amount,
    required super.position,
    required this.rise,
    this.color = AppColors.gold,
  }) : super(priority: 19, anchor: Anchor.center);

  final int amount;

  /// How far up the popup travels, in world pixels.
  final double rise;

  final Color color;

  static const double _duration = 0.85;
  double _elapsed = 0;
  late final Vector2 _origin = position.clone();

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) {
      removeFromParent();
      return;
    }
    final t = (_elapsed / _duration).clamp(0.0, 1.0);
    position = _origin - Vector2(0, rise * Curves.easeOutCubic.transform(t));
  }

  @override
  void render(ui.Canvas canvas) {
    final t = (_elapsed / _duration).clamp(0.0, 1.0);
    final scale = 0.25 + 1.25 * Curves.easeOutBack.transform((t * 2.2).clamp(0.0, 1.0));
    final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);

    canvas.save();
    canvas.scale(scale);

    final painter = TextPainter(
      text: TextSpan(
        text: '+$amount',
        style: feedbackStyle(
          fontSize: 22,
          weight: FontWeight.w700,
          color: color.withValues(alpha: opacity),
        ).copyWith(
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.8 * opacity),
              blurRadius: 4,
            ),
            Shadow(
              color: color.withValues(alpha: 0.6 * opacity),
              blurRadius: 14,
            ),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(-painter.width / 2, -painter.height / 2),
    );
    canvas.restore();
  }
}
