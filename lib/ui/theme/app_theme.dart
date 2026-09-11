/// The single source of colour and type for the whole game.
///
/// easy-mathriss kept two divergent copies of its tile palette, one in the
/// board component and one in the widget layer. There is exactly one here.
library;

import 'package:flutter/material.dart';

import '../../core/board/tile.dart';

abstract final class AppColors {
  static const background = Color(0xFF0A0E16);

  /// Shows through the gaps between blocks, so it doubles as the mortar.
  static const boardBackground = Color(0xFF161C28);
  static const gridLine = Color(0xFF1C2740);
  static const accent = Color(0xFF34D6D0);
  static const text = Color(0xFFE8F0FF);
  static const textDim = Color(0xFF8FA3C4);
  static const gold = Color(0xFFFFC64B);
  static const danger = Color(0xFFFF5D5D);

  static const selection = Color(0xFF4FE3DC);
  static const hint = Color(0xFFFFC64B);

  /// Glyph colour on a light tile.
  static const glyphOnLight = Color(0xFF16233A);

  /// Glyph colour on a dark tile.
  static const glyphOnDark = Color(0xFFFFFFFF);
}

/// Every glyph gets its own identity colour.
///
/// Digits run a full spectrum so a row reads as distinct objects rather than a
/// wall of one hue - the single biggest reason the first build looked flat.
/// Operators stay a desaturated family on purpose: they are the punctuation of
/// an equation, and letting them compete with the digits makes runs harder to
/// scan.
const Map<String, Color> glyphColors = {
  // Jewel tones, not pastels. Coloured glass gets its character from saturation
  // held under a bright highlight; a pale base leaves nothing for the light to
  // do and the block reads as frosted plastic.
  '0': Color(0xFF8695AD), // smoke
  '1': Color(0xFFE8F2FF), // clear
  '2': Color(0xFFFFC21F), // amber
  '3': Color(0xFFFF8A2B), // orange
  '4': Color(0xFF3FC96B), // emerald
  '5': Color(0xFF19C6C0), // turquoise
  '6': Color(0xFF3D9BFF), // azure
  '7': Color(0xFF7B62FF), // violet
  '8': Color(0xFFB84DFF), // magenta
  '9': Color(0xFFFF4D88), // rose

  '+': Color(0xFF46617A),
  '-': Color(0xFF46617A),
  '*': Color(0xFF3C5670),
  '/': Color(0xFF3C5670),
  '^': Color(0xFF1F7A46),

  '=': Color(0xFF6A46B8),
  '<': Color(0xFF5C3CA8),
  '>': Color(0xFF5C3CA8),
  '!': Color(0xFF9E3A63),
};

/// Fill colour for a bomb tile.
const Color bombColor = Color(0xFFFF4A2B);

/// The identity colour of [tile].
Color tileColor(Tile tile) {
  if (tile.isStone) return const Color(0xFF606060); // Dark grey
  if (tile.isFrozen) return const Color(0xFF80D8FF); // Light blue
  if (tile.special == SpecialKind.wildcard) return const Color(0xFF9C27B0); // Purple
  if (tile.isBomb) return bombColor;
  return glyphColors[tile.glyph] ?? const Color(0xFF54708A);
}

/// Glyph colour that stays legible on [fill].
Color glyphColorOn(Color fill) => fill.computeLuminance() > 0.45
    ? AppColors.glyphOnLight
    : AppColors.glyphOnDark;

/// [color] brightened by [amount] (0..1), keeping its colour.
///
/// Saturation is nudged up alongside lightness on purpose. Raising HSL
/// lightness alone walks a hue toward white, so a highlight built that way
/// bleaches the tile; holding saturation keeps the highlight tinted, which is
/// what a lit edge of coloured glass actually looks like.
Color lighten(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + amount * 0.45).clamp(0.0, 1.0))
      .toColor();
}

/// [color] deepened by [amount] (0..1).
///
/// Saturation rises as it darkens, the way thicker glass reads richer.
Color darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + amount * 0.25).clamp(0.0, 1.0))
      .toColor();
}

abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ),
      );
}
