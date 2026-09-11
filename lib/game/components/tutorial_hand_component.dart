import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import '../../core/board/tile.dart';
import 'board_component.dart';

/// A pointing hand emoji that gestures between two tiles to teach the swap.
class TutorialHandComponent extends PositionComponent with HasAncestor<BoardComponent> {
  TutorialHandComponent({
    required this.a,
    required this.b,
  });

  final Coord a;
  final Coord b;

  @override
  Future<void> onLoad() async {
    final cellSize = ancestor.cellSize;
    
    // The hand emoji itself
    final hand = TextComponent(
      text: '👆',
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: cellSize * 0.8,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(2, 2))
          ],
        ),
      ),
    );
    // Center the emoji on its anchor
    hand.anchor = Anchor.center;
    add(hand);

    // Position self at tile A
    position = ancestor.centerOf(a) + Vector2(0, cellSize * 0.2);

    // Animate swiping to tile B and back
    final targetPos = ancestor.centerOf(b) + Vector2(0, cellSize * 0.2);
    
    add(
      MoveToEffect(
        targetPos,
        EffectController(
          duration: 0.8,
          reverseDuration: 0.4,
          infinite: true,
          curve: Curves.easeInOut,
        ),
      ),
    );
  }
}
