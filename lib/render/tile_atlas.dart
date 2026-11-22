import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Loads the tile artwork (built from the concept tile sheet by
/// `tools/build_tiles.py`) once and shares it between every globe.
///
/// * `tile_plates.png`  – 4x8 atlas of 256 px plates (rows 0-3 hexagons, 4-7 pentagons). A plate is the metal
///   frame (plus the mine / exploded artwork) and is mapped onto each cell
///   corner-by-corner, so frames always line up with the cell outline.
/// * `glyph_digits.png` – white alpha layers (glow / core / hot) for digits 1-8,
///   tinted at runtime so the colour-blind palettes keep working.
/// * `glyph_flag.png`   – the upright hologram flag.
///
/// If loading fails (tests, missing assets) [ready] stays false and the
/// renderer falls back to its flat-colour look.
class TileAtlas {
  const TileAtlas._();

  /// Edge length of one plate / glyph cell in the source images.
  static const double cell = 256;

  /// Circumradius of the hexagon inside a plate cell (texture pixels). Cell
  /// corners are mapped slightly inside the art edge to avoid fringe pixels.
  static const double hexRadius = 118;

  // Plate indices (order must match ORDER in tools/build_tiles.py).
  static const int hidden = 0;
  static const int flag = 1;
  static const int mine = 2;
  static const int exploded = 3;
  static const int blank = 4;
  static const int number1 = 5; // numbers 1..8 -> 5..12
  static const int flagWrong = 13;

  /// Pentagon plates use the same order, this many slots further on.
  static const int pentagonOffset = 16;

  static ui.Image? plates;
  static ui.Image? digits;
  static ui.Image? flagGlyph;
  static ui.ImageShader? _shader;
  static ui.ImageShader? _reliefShader;
  static Future<void>? _loading;

  static bool get ready => plates != null && _shader != null;
  static bool get glyphsReady => digits != null && flagGlyph != null;
  static ui.ImageShader? get shader => _shader;

  /// Same plates with relief baked in (null if that file failed to load).
  static ui.ImageShader? get reliefShader => _reliefShader;

  /// Starts loading (once) and completes when finished, successfully or not.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final p = await _image('assets/tiles/tile_plates.png');
      final d = await _image('assets/tiles/glyph_digits.png');
      final f = await _image('assets/tiles/glyph_flag.png');
      plates = p;
      digits = d;
      flagGlyph = f;
      _shader = _makeShader(p);
    } catch (_) {
      // Keep the flat-colour fallback.
    }
    try {
      final r = await _image('assets/tiles/tile_plates_relief.png');
      _reliefShader = _makeShader(r);
    } catch (_) {
      // Relief is optional.
    }
  }

  static ui.ImageShader _makeShader(ui.Image image) => ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Float64List.fromList(const <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        filterQuality: ui.FilterQuality.medium,
      );

  static Future<ui.Image> _image(String key) async {
    final data = await rootBundle.load(key);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Top-left corner of plate [index] in the atlas.
  static double originX(int index) => (index % 4) * cell;
  static double originY(int index) => (index ~/ 4) * cell;
}
