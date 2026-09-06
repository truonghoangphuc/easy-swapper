import 'package:easy_swapper/core/board/board_model.dart';
import 'package:easy_swapper/core/board/tile.dart';

/// Builds a board from one string per row, where `.` is an empty cell.
///
/// Every row must be the same length. Tile ids are assigned in reading order,
/// so a test can assert on identity after a compaction.
BoardModel boardFrom(List<String> rows) {
  final height = rows.length;
  final width = rows.first.length;
  assert(rows.every((r) => r.length == width), 'ragged board');

  final board = BoardModel(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final glyph = rows[y][x];
      if (glyph == '.') continue;
      board.set(x, y, Tile(id: board.ids.nextId(), glyph: glyph, kind: kindOf(glyph)));
    }
  }
  return board;
}

/// Classifies a glyph the way the generator would.
TileKind kindOf(String glyph) {
  if (glyph.codeUnitAt(0) >= 0x30 && glyph.codeUnitAt(0) <= 0x39) {
    return TileKind.digit;
  }
  if ('+-*/^'.contains(glyph)) return TileKind.arithmetic;
  return TileKind.comparison;
}
