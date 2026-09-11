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

/// The glyph an electric tile carries.
const String electricGlyph = '\u{26A1}';

/// Power-up behaviours.
enum SpecialKind {
  /// Detonates when swapped, clearing its whole row and column.
  bomb,

  /// Destroys every brick sharing the glyph of whatever it is swapped with.
  electric,

  /// Stands in for any digit when tokenizing.
  wildcard,
}

/// How many impacts a casing absorbs before the brick underneath is playable.
///
/// The brick keeps its glyph the whole time - the player can see what is coming
/// and plan around it - but an encased brick neither tokenizes nor swaps, so
/// each one is a hole in the equations still available. That is the whole cost
/// of the mechanic, and it is why the supply is capped in [GameSession] rather
/// than left to the draw.
abstract final class Armor {
  static const int none = 0;

  /// One impact.
  static const int stone = 1;

  /// Two impacts.
  static const int diamond = 2;
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
    this.armor = Armor.none,
  });

  final int id;
  final String glyph;
  final TileKind kind;
  final SpecialKind? special;

  /// Impacts still needed before this brick becomes an ordinary one.
  ///
  /// 0 is a plain brick, 1 is stone, 2 is diamond. See [Armor].
  final int armor;

  bool get isSpecial => special != null;

  bool get isBomb => special == SpecialKind.bomb;

  bool get isElectric => special == SpecialKind.electric;

  bool get isWildcard => special == SpecialKind.wildcard;

  /// True while a casing is still in the way.
  bool get isEncased => armor > Armor.none;

  /// A bomb or an electric: something that fires when it is swapped.
  bool get isPowerUp => isBomb || isElectric;

  /// Whether the player may pick this brick up at all.
  ///
  /// A bomb and an electric both swap - that is how they are triggered. A
  /// casing is what pins a brick in place.
  bool get canSwap => !isEncased;

  /// True for anything that cannot take part in an equation as it stands.
  ///
  /// The budget in [GameSession] counts these together rather than per type:
  /// a bomb, an electric and an encased brick are all the same thing from the
  /// board's point of view - a cell the player cannot build a run through - and
  /// per-type caps let the total drift.
  bool get isObstacle => isBomb || isElectric || isEncased;

  /// A bomb tile carrying [id].
  factory Tile.bomb(int id) => Tile(
        id: id,
        glyph: bombGlyph,
        kind: TileKind.special,
        special: SpecialKind.bomb,
      );

  /// An electric tile carrying [id].
  factory Tile.electric(int id) => Tile(
        id: id,
        glyph: electricGlyph,
        kind: TileKind.special,
        special: SpecialKind.electric,
      );

  /// A wildcard tile carrying [id] that can act as any digit.
  factory Tile.wildcard(int id) => Tile(
        id: id,
        glyph: '?',
        kind: TileKind.special,
        special: SpecialKind.wildcard,
      );

  /// This brick with one layer of casing taken off.
  Tile cracked() =>
      armor <= Armor.none ? this : copyWith(armor: armor - 1);

  /// This brick sealed under [layers] of casing.
  Tile encased(int layers) => copyWith(armor: layers);

  /// The glyph as the expression engine should see it.
  ///
  /// Specials return `null` so a run containing one fails to tokenize, which is
  /// exactly the abort behaviour the scanner expects. An encased brick does the
  /// same: its glyph is visible to the *player*, which is the point of the
  /// mechanic, but it is not yet available to an equation.
  String? get scanGlyph {
    if (special == SpecialKind.wildcard) return glyph; // '?'
    return (isSpecial || isEncased) ? null : glyph;
  }

  Tile copyWith({
    int? id,
    String? glyph,
    TileKind? kind,
    SpecialKind? special,
    int? armor,
  }) =>
      Tile(
        id: id ?? this.id,
        glyph: glyph ?? this.glyph,
        kind: kind ?? this.kind,
        special: special ?? this.special,
        armor: armor ?? this.armor,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'glyph': glyph,
        'kind': kind.name,
        if (special != null) 'special': special!.name,
        if (armor > Armor.none) 'armor': armor,
      };

  factory Tile.fromJson(Map<String, dynamic> json) {
    // `isStone` is how the pre-armour builds spelled a one-hit casing. A save
    // written by one of those must still load, so it maps onto the new field
    // rather than being dropped.
    final legacyStone = json['isStone'] as bool? ?? false;
    final special = json['special'] as String?;
    return Tile(
      id: json['id'] as int,
      glyph: json['glyph'] as String,
      kind: TileKind.values.byName(json['kind'] as String),
      // `rowClear` and `columnClear` were declared and never produced; a save
      // cannot contain them, but byName would throw rather than degrade if one
      // ever did.
      special: special != null
          ? SpecialKind.values
              .where((k) => k.name == special)
              .firstOrNull
          : null,
      armor: json['armor'] as int? ?? (legacyStone ? Armor.stone : Armor.none),
    );
  }

  @override
  String toString() {
    final casing = switch (armor) {
      Armor.none => '',
      Armor.stone => ' stone',
      _ => ' diamond',
    };
    return 'Tile($glyph#$id$casing)';
  }
}

/// Whether a swap of [a] and [b] is allowed to be attempted at all.
///
/// Both must be free to move - except that a power-up may always be swapped
/// into a casing. That exception is load-bearing rather than generous: without
/// it, an electric or a bomb ringed by encased bricks cannot be triggered at
/// all, and a board can reach a state where the only power-up on it is
/// unusable and the run is dead. Letting a power-up break into stone also
/// makes it the obvious answer to armour, which is how a player expects it to
/// read.
///
/// Defined once, here, because [GameSession.trySwap] and the move solver must
/// never disagree about it: the solver decides whether the board is
/// deadlocked, and a deadlock wipes the run's whole score.
bool canSwapPair(Tile? a, Tile? b) =>
    ((a?.canSwap ?? true) && (b?.canSwap ?? true)) ||
    (a?.isPowerUp ?? false) ||
    (b?.isPowerUp ?? false);

/// True if [tile] carries an arithmetic or comparison glyph.
///
/// Digits, bombs and empty cells are all false. An **encased** operator is
/// still true: it is not usable yet, but it occupies a cell and it will become
/// usable, so every adjacency and crowding rule has to see it coming.
bool isOperator(Tile? tile) =>
    tile != null &&
    (tile.kind == TileKind.arithmetic || tile.kind == TileKind.comparison);

/// True if [tile] is an operator the player can actually build a run through.
///
/// The supply floors count these; the cap counts [isOperator]. The asymmetry is
/// deliberate and mirrors the one already applied to the preview queue: a cell
/// can crowd the board without contributing anything to it.
bool isUsableOperator(Tile? tile) => isOperator(tile) && !tile!.isEncased;

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
