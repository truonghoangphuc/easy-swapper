/// Board coordinates and the tile value model. Pure Dart.
library;

/// An immutable grid coordinate.
class Coord {
  const Coord(this.x, this.y);

  final int x;
  final int y;

  Coord copyWith({int? x, int? y}) => Coord(x ?? this.x, y ?? this.y);

  /// True when [other] is orthogonally adjacent (never diagonal).
  bool isAdjacentTo(Coord other) =>
      (x - other.x).abs() + (y - other.y).abs() == 1;

  @override
  bool operator ==(Object other) =>
      other is Coord && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

/// What role a glyph plays in an equation.
enum TileKind {
  /// A single character, 0 through 9.
  digit,

  /// One of `+ - * / ^`.
  arithmetic,

  /// One of `= < > !`, possibly fusing with a neighbour into `<=`, `>=`, `!=`.
  comparison,

  /// A power-up. Never tokenizes, so it always aborts a scan that reaches it.
  special,
}

/// The glyph a bomb tile carries.
const String bombGlyph = '\u{1F4A3}';

/// Power-up behaviours.
enum SpecialKind {
  /// Detonates when swapped, clearing its whole row and column.
  bomb,

  /// Clears the whole row.
  rowClear,

  /// Clears the whole column.
  columnClear,

  /// Stands in for any digit when tokenizing.
  wildcard,
}

/// A single occupant of one board cell.
///
/// [id] is stable for the life of the tile. That is what lets the render layer
/// animate a tile from its old cell to its new one after a compaction, rather
/// than destroying and rebuilding the component.
class Tile {
  const Tile({
    required this.id,
    required this.glyph,
    required this.kind,
    this.special,
  });

  final int id;
  final String glyph;
  final TileKind kind;
  final SpecialKind? special;

  bool get isSpecial => special != null;

  bool get isBomb => special == SpecialKind.bomb;

  /// A bomb tile carrying [id].
  factory Tile.bomb(int id) => Tile(
        id: id,
        glyph: bombGlyph,
        kind: TileKind.special,
        special: SpecialKind.bomb,
      );

  /// The glyph as the expression engine should see it.
  ///
  /// Specials return `null` so a run containing one fails to tokenize, which is
  /// exactly the abort behaviour the scanner expects.
  String? get scanGlyph => isSpecial ? null : glyph;

  Tile copyWith({int? id, String? glyph, TileKind? kind, SpecialKind? special}) =>
      Tile(
        id: id ?? this.id,
        glyph: glyph ?? this.glyph,
        kind: kind ?? this.kind,
        special: special ?? this.special,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'glyph': glyph,
        'kind': kind.name,
        if (special != null) 'special': special!.name,
      };

  factory Tile.fromJson(Map<String, dynamic> json) => Tile(
        id: json['id'] as int,
        glyph: json['glyph'] as String,
        kind: TileKind.values.byName(json['kind'] as String),
        special: json['special'] != null
            ? SpecialKind.values.byName(json['special'] as String)
            : null,
      );

  @override
  String toString() => 'Tile($glyph#$id)';
}

/// True if [tile] carries an arithmetic or comparison glyph.
///
/// Digits, bombs and empty cells are all false.
bool isOperator(Tile? tile) =>
    tile != null &&
    (tile.kind == TileKind.arithmetic || tile.kind == TileKind.comparison);

/// Hands out unique, monotonically increasing tile ids.
///
/// Owned by the board so that a seeded test run is fully reproducible.
class TileIdGenerator {
  TileIdGenerator();
  
  int _next = 0;

  int nextId() => _next++;

  /// Restores the counter, for load-from-save.
  void restore(int value) => _next = value;

  int get current => _next;

  Map<String, dynamic> toJson() => {'next': _next};

  factory TileIdGenerator.fromJson(Map<String, dynamic> json) {
    final gen = TileIdGenerator();
    gen.restore(json['next'] as int);
    return gen;
  }
}
