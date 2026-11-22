import 'package:flutter/material.dart';

/// Central visual configuration. Everything the globe renderer and UI use for
/// colour, lighting and outline styling lives here so the look can be tuned in
/// one place (and later swapped per planet environment).
class HexfallTheme {
  const HexfallTheme._();

  // --- Interface palette ------------------------------------------------------
  static const Color spaceBlack = Color(0xFF02050B);
  static const Color spaceDeep = Color(0xFF071326);
  static const Color panel = Color(0xE60A1626);
  static const Color cyan = Color(0xFF3FE0FF);
  static const Color cyanSoft = Color(0xFF7FD6F2);
  static const Color blue = Color(0xFF2B7BFF);
  static const Color amber = Color(0xFFFFB347);
  static const Color magenta = Color(0xFFFF4FD8);
  static const Color danger = Color(0xFFFF4B4B);
  static const Color good = Color(0xFF45F0A0);
  static const Color textPrimary = Color(0xFFE6F6FF);
  static const Color textDim = Color(0xFF86A5B8);

  // --- Globe lighting (view space, camera looks down -Z) -----------------------
  /// Direction *towards* the sun in view space (normalised at use).
  static const List<double> lightDirection = [-0.45, 0.55, 0.70];
  static const double ambient = 0.46;
  static const double diffuse = 0.80;

  /// Fresnel rim light colour, 0..1 rgb.
  static const List<double> rimColor = [0.20, 0.72, 1.00];
  static const double rimStrength = 0.55;

  // --- Tiles --------------------------------------------------------------------
  /// Fraction of the cell kept when drawing (1 = no gap). The gap between
  /// tiles gives the holographic "tile" look.
  static const double tileInset = 0.92;

  /// Hologram tint blended into the planet colour of every tile (rgb, amount).
  static const List<double> holoTint = [0.04, 0.22, 0.38];
  static const double holoTintAmount = 0.30;

  static const Color outline = Color(0xFF45D9FF);
  static const double outlineAlpha = 0.55;
  static const double outlineGlowAlpha = 0.14;

  // --- Interaction colours (rgb 0..1, blended over tile colour) -------------------
  static const List<double> selectedColor = [0.75, 0.98, 1.0];
  static const List<double> neighbourColor = [1.0, 0.70, 0.28];
  static const List<double> hoverColor = [0.30, 0.90, 1.0];
  static const List<double> markedColor = [1.0, 0.38, 0.20];
  static const List<double> pentagonColor = [1.0, 0.31, 0.85];

  // --- Atmosphere ----------------------------------------------------------------
  static const Color atmosphere = Color(0xFF39B8FF);

  static ThemeData materialTheme() {
    const scheme = ColorScheme.dark(
      primary: cyan,
      secondary: amber,
      surface: spaceDeep,
      error: danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: spaceBlack,
    );
  }
}

/// Packs 0..1 rgb into an opaque ARGB int.
int packRgb(double r, double g, double b) {
  final ri = (r < 0 ? 0 : (r > 1 ? 1 : r)) * 255;
  final gi = (g < 0 ? 0 : (g > 1 ? 1 : g)) * 255;
  final bi = (b < 0 ? 0 : (b > 1 ? 1 : b)) * 255;
  return 0xFF000000 | (ri.toInt() << 16) | (gi.toInt() << 8) | bi.toInt();
}
