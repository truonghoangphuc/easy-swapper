/// The tile waiting to drop into each column. Pure Dart.
///
/// Refills used to draw from the generator on demand, which is fine until the
/// player is shown what is coming: a preview is only worth having if it is the
/// truth. The queue makes it the truth - the next tile to enter a column is
/// decided, held, and displayed before it is needed.
///
/// One slot per column, so the strip above the board lines up with the column
/// each brick will fall into. That alignment is the point, and it is not free:
/// committing a tile to a column fixes it before anyone knows which cell it
/// lands in, which is placement freedom the refill would otherwise use to keep
/// operators apart. What can be chosen is *which columns* receive operators in
/// the first place, and [GameSession.replenishQueue] spends that carefully.
library;

import 'tile.dart';

class TileQueue {
  TileQueue(this.width) : _slots = List<Tile?>.filled(width, null);

  /// One slot per board column.
  final int width;

  final List<Tile?> _slots;

  /// The queued tile for each column, in column order.
  List<Tile?> get slots => List.unmodifiable(_slots);

  bool get isFull => _slots.every((t) => t != null);

  int get count => _slots.where((t) => t != null).length;

  Tile? peek(int column) => _slots[column];

  /// Columns with nothing queued, in column order.
  List<int> emptyColumns() => [
        for (var x = 0; x < width; x++)
          if (_slots[x] == null) x,
      ];

  /// Removes and returns the tile queued for [column], leaving the slot empty
  /// until the next fill.
  Tile? take(int column) {
    final tile = _slots[column];
    _slots[column] = null;
    return tile;
  }

  void fill(int column, Tile tile) => _slots[column] = tile;

  /// How many queued tiles are operators, so a caller can count them against a
  /// board budget before they land.
  int operatorCount() => _slots.where(isOperator).length;

  /// How many queued tiles are bombs, for the same reason.
  int bombCount() => _slots.where((t) => t?.isBomb ?? false).length;

  /// How many queued tiles are comparison glyphs.
  int comparisonCount() =>
      _slots.where((t) => t?.kind == TileKind.comparison).length;

  void clear() {
    for (var x = 0; x < width; x++) {
      _slots[x] = null;
    }
  }

  Map<String, dynamic> toJson() => {
        'width': width,
        'slots': _slots.map((t) => t?.toJson()).toList(),
      };

  factory TileQueue.fromJson(Map<String, dynamic> json) {
    final width = json['width'] as int;
    final queue = TileQueue(width);
    final slotsData = json['slots'] as List;
    for (var x = 0; x < width; x++) {
      if (slotsData[x] != null) {
        queue._slots[x] = Tile.fromJson(slotsData[x] as Map<String, dynamic>);
      }
    }
    return queue;
  }
}
