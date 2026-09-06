/// The next-drop strip: one brick per column, showing what enters it next.
///
/// Sits directly above the board and shares its column pitch and its brick
/// size, so a brick in the strip lines up with the column it will fall into.
/// That alignment is the whole point - a preview the player has to map back onto
/// the board by counting is no better than no preview.
library;

import 'package:flame/components.dart';
import 'package:flutter/material.dart'
    show Canvas, FontWeight, Paint, RRect, Radius, Rect, TextStyle;

import '../../core/board/tile_queue.dart';
import '../../ui/theme/app_theme.dart';
import 'tile_component.dart';

class PreviewComponent extends PositionComponent {
  PreviewComponent({
    required this.queue,
    required this.cellSize,
    required super.position,
  }) : super(size: Vector2(queue.width * cellSize, cellSize));

  final TileQueue queue;

  /// The board's cell pitch, and the preview brick's size: they are the same, so
  /// a brick in the strip is the brick that will land.
  final double cellSize;

  final Map<int, TileComponent> _bricks = {};

  @override
  Future<void> onLoad() async {
    await sync();
  }

  /// Centre of the preview slot for [column], in local pixels.
  Vector2 slotCenter(int column) =>
      Vector2((column + 0.5) * cellSize, size.y / 2);

  /// Rebuilds the strip from the queue, touching only columns that changed.
  Future<void> sync() async {
    final fresh = <TileComponent>[];

    for (var x = 0; x < queue.width; x++) {
      final tile = queue.peek(x);
      final existing = _bricks[x];
      if (existing != null && existing.tile.id == tile?.id) continue;

      existing?.removeFromParent();
      _bricks.remove(x);
      if (tile == null) continue;

      final brick = TileComponent(
        tile: tile,
        position: slotCenter(x),
        cellSize: cellSize,
      );
      _bricks[x] = brick;
      fresh.add(brick);
    }

    if (fresh.isNotEmpty) await addAll(fresh);
  }

  @override
  void render(Canvas canvas) {
    // A rail beneath the bricks, marking where each column feeds the board.
    final rail = Paint()..color = AppColors.gridLine;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.y + cellSize * 0.10, size.x, cellSize * 0.035),
        Radius.circular(cellSize * 0.02),
      ),
      rail,
    );
    for (var x = 0; x < queue.width; x++) {
      canvas.drawRect(
        Rect.fromLTWH(
          (x + 0.5) * cellSize - cellSize * 0.012,
          size.y + cellSize * 0.02,
          cellSize * 0.024,
          cellSize * 0.09,
        ),
        rail,
      );
    }
    super.render(canvas);
  }
}

/// The `NEXT` caption above the strip.
class PreviewLabel extends TextComponent {
  PreviewLabel({required super.position, required double cellSize})
      : super(
          text: 'NEXT',
          anchor: Anchor.centerLeft,
          textRenderer: TextPaint(
            style: TextStyle(
              fontFamily: 'Baloo2',
              color: AppColors.textDim,
              fontSize: cellSize * 0.20,
              fontWeight: FontWeight.w800,
              letterSpacing: cellSize * 0.03,
            ),
          ),
        );
}
