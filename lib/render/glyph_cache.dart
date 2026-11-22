import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../persistence/models.dart';
import 'tile_atlas.dart';

/// Number colours per palette (index 0 is unused; 1..8 are the mine counts).
class NumberPalettes {
  const NumberPalettes._();

  static const List<int> standard = [
    0, 0xFF40D8FF, 0xFF4CE07A, 0xFFFFC040, 0xFFB07CFF, 0xFFFF553A, 0xFF20E0B8, 0xFFFF4FD8, 0xFFFFFFFF,
  ];

  /// Okabe–Ito based: distinguishable for the common colour-vision deficiencies.
  static const List<int> colorBlind = [
    0, 0xFF56B4E9, 0xFFF0E442, 0xFFFF8040, 0xFF8FA8FF, 0xFFE69F00, 0xFFCC79A7, 0xFF3FD9A4, 0xFFFFFFFF,
  ];

  /// Warm/cool alternation with maximum luminance contrast on dark tiles.
  static const List<int> highContrast = [
    0, 0xFFFFFFFF, 0xFFFFE600, 0xFF7DF9FF, 0xFFFFA0FF, 0xFFFFC040, 0xFF9CFF9C, 0xFFFFFFFF, 0xFFFFFF99,
  ];

  static List<int> of(NumberPalette p) => switch (p) {
        NumberPalette.standard => standard,
        NumberPalette.colorBlind => colorBlind,
        NumberPalette.highContrast => highContrast,
      };
}

/// Sprite indices inside the atlas.
class Sprite {
  const Sprite._();
  static const int digit1 = 0; // digits 1..8 -> 0..7
  static const int flag = 8;
  static const int flagWrong = 9;
  static const int mine = 10;
  static const int mineExploded = 11;
  static const int count = 12;

  /// Radius (in sprite pixels) that corresponds to a cell's corner distance.
  /// The on-screen scale of a sprite is tileRadiusPx * [factor] / [natural].
  /// 118 = the hexagon radius used when the tile plates are mapped onto cells,
  /// so glyphs drawn from the tile art land exactly where the art put them.
  static const double natural = 118;
  static const double factor = 1.0;
}

/// Pre-rendered glyphs for tile contents.
///
/// All numbers, flags and mines are drawn once into a single image (the
/// "atlas"). Each frame every visible glyph is then submitted in ONE
/// `drawRawAtlas` call, instead of hundreds of text draws with blurred
/// shadows. Until the atlas has finished building (a few milliseconds after
/// start-up) a plain vector fallback is used.
class GlyphCache {
  GlyphCache(this.palette, {this.onReady}) {
    _buildFallbackDigits();
    _buildAtlas();
  }

  final NumberPalette palette;
  final void Function()? onReady;

  static const double cell = 256;

  ui.Image? atlas;
  bool _disposed = false;

  bool get ready => atlas != null;

  /// Source rectangle (left, top, right, bottom) of [sprite] in the atlas.
  static void rectOf(int sprite, Float32List out, int offset) {
    out[offset] = sprite * cell;
    out[offset + 1] = 0;
    out[offset + 2] = sprite * cell + cell;
    out[offset + 3] = cell;
  }

  // --- Atlas -----------------------------------------------------------------

  Future<void> _buildAtlas() async {
    try {
      await TileAtlas.load();
      if (_disposed) return;
      final art = TileAtlas.glyphsReady;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final colors = NumberPalettes.of(palette);

      void at(int sprite, void Function(Canvas c) draw) {
        canvas.save();
        canvas.translate(sprite * cell + cell / 2, cell / 2);
        draw(canvas);
        canvas.restore();
      }

      for (var n = 1; n <= 8; n++) {
        at(Sprite.digit1 + n - 1, (c) {
          if (art) {
            _drawDigitArt(c, n, Color(colors[n]));
          } else {
            c.scale(2.0, 2.0); // vector glyphs are authored for a 128 px cell
            _drawDigitSprite(c, n, Color(colors[n]));
          }
        });
      }
      at(Sprite.flag, (c) {
        if (art) {
          _drawFlagArt(c, wrong: false);
        } else {
          c.scale(2.0, 2.0);
          _drawFlagSprite(c, wrong: false);
        }
      });
      at(Sprite.flagWrong, (c) {
        if (art) {
          _drawFlagArt(c, wrong: true);
        } else {
          c.scale(2.0, 2.0);
          _drawFlagSprite(c, wrong: true);
        }
      });
      // Mines are part of the tile plates when the art is available; these
      // vector sprites are only the fallback.
      at(Sprite.mine, (c) {
        c.scale(2.0, 2.0);
        _drawMineSprite(c, exploded: false);
      });
      at(Sprite.mineExploded, (c) {
        c.scale(2.0, 2.0);
        _drawMineSprite(c, exploded: true);
      });

      final picture = recorder.endRecording();
      final image = await picture.toImage((cell * Sprite.count).toInt(), cell.toInt());
      picture.dispose();
      if (_disposed) {
        image.dispose();
        return;
      }
      atlas = image;
      onReady?.call();
    } catch (_) {
      // Keep using the vector fallback if image creation is unavailable.
    }
  }

  /// Neon digit from the tile-art masks: glow, bright core and a hot centre
  /// line, each tinted from the palette colour.
  void _drawDigitArt(Canvas canvas, int n, Color color) {
    final img = TileAtlas.digits!;
    const dst = Rect.fromLTWH(-cell / 2, -cell / 2, cell, cell);
    Color mixWhite(double k) => Color.lerp(color, const Color(0xFFFFFFFF), k)!;
    final tints = <Color>[color.withAlpha(235), mixWhite(0.22), mixWhite(0.72)];
    for (var row = 0; row < 3; row++) {
      final src = Rect.fromLTWH((n - 1) * cell, row * cell, cell, cell);
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(tints[row], BlendMode.srcIn),
      );
    }
  }

  void _drawFlagArt(Canvas canvas, {required bool wrong}) {
    final img = TileAtlas.flagGlyph!;
    const dst = Rect.fromLTWH(-cell / 2, -cell / 2, cell, cell);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    if (wrong) {
      final x = Paint()
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF3030);
      canvas.drawLine(const Offset(-70, -70), const Offset(70, 70), x);
      canvas.drawLine(const Offset(70, -70), const Offset(-70, 70), x);
    }
  }

  /// Glowing digit. The tile's own outline provides the frame, so the glyph
  /// never has to line up with a tile's orientation.
  void _drawDigitSprite(Canvas canvas, int n, Color color) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 72, fontWeight: FontWeight.w700),
    )
      ..pushStyle(ui.TextStyle(
        color: color,
        fontSize: 72,
        fontWeight: FontWeight.w700,
        shadows: [
          ui.Shadow(color: color.withAlpha(230), blurRadius: 16),
          ui.Shadow(color: color.withAlpha(140), blurRadius: 30),
        ],
      ))
      ..addText('$n');
    final p = builder.build()..layout(const ui.ParagraphConstraints(width: 110));
    canvas.drawParagraph(p, Offset(-55, -p.height / 2));
    p.dispose();
  }

  /// Hologram flag on a glowing hex platform.
  void _drawFlagSprite(Canvas canvas, {required bool wrong}) {
    const cyan = Color(0xFF5CE1FF);
    canvas.drawRect(
      const Rect.fromLTRB(-22, -48, 22, 30),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 30),
          const Offset(0, -48),
          [cyan.withAlpha(90), cyan.withAlpha(0)],
        ),
    );
    final plat = Path();
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final x = math.cos(a) * 40, y = 30 + math.sin(a) * 15;
      if (i == 0) {
        plat.moveTo(x, y);
      } else {
        plat.lineTo(x, y);
      }
    }
    plat.close();
    canvas.drawPath(plat, Paint()..color = const Color(0xCC0B2236));
    canvas.drawPath(
      plat,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = cyan.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      plat,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = cyan,
    );
    canvas.drawLine(
      const Offset(-8, -44),
      const Offset(-8, 30),
      Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE6FAFF),
    );
    final banner = Path()
      ..moveTo(-8, -44)
      ..lineTo(38, -26)
      ..lineTo(-8, -8)
      ..close();
    canvas.drawPath(
      banner,
      Paint()
        ..color = cyan.withAlpha(120)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(banner, Paint()..color = cyan);
    if (wrong) {
      final x = Paint()
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF3030);
      canvas.drawLine(const Offset(-44, -44), const Offset(44, 44), x);
      canvas.drawLine(const Offset(44, -44), const Offset(-44, 44), x);
    }
  }

  /// Spiked red mine with a glowing core.
  void _drawMineSprite(Canvas canvas, {required bool exploded}) {
    final glowColor = exploded ? const Color(0xFFFFB040) : const Color(0xFFFF3A2A);
    final glowR = exploded ? 62.0 : 52.0;
    canvas.drawCircle(
      Offset.zero,
      glowR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          glowR,
          [glowColor.withAlpha(exploded ? 230 : 150), glowColor.withAlpha(0)],
        ),
    );
    final spike = Paint()
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF6A55);
    for (var i = 0; i < 10; i++) {
      final a = i * math.pi / 5;
      canvas.drawLine(
        Offset(math.cos(a) * 24, math.sin(a) * 24),
        Offset(math.cos(a) * 46, math.sin(a) * 46),
        spike,
      );
    }
    canvas.drawCircle(Offset.zero, 28, Paint()..color = const Color(0xFF241014));
    canvas.drawCircle(
      Offset.zero,
      28,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF8A3A38),
    );
    canvas.drawCircle(
      Offset.zero,
      16,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          16,
          [exploded ? const Color(0xFFFFF2C0) : const Color(0xFFFF8A70), const Color(0xFFE02818)],
        ),
    );
    canvas.drawCircle(const Offset(-8, -9), 5, Paint()..color = const Color(0x66FFFFFF));
  }

  // --- Vector fallback (used until the atlas is ready) ---------------------------

  final Map<int, ui.Paragraph> _digits = {};

  void _buildFallbackDigits() {
    final colors = NumberPalettes.of(palette);
    for (var n = 1; n <= 8; n++) {
      final color = Color(colors[n]);
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 32, fontWeight: FontWeight.w800),
      )
        ..pushStyle(ui.TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w800))
        ..addText('$n');
      _digits[n] = builder.build()..layout(const ui.ParagraphConstraints(width: 48));
    }
  }

  static final Paint _fallbackFlag = Paint()..color = const Color(0xFF5CE1FF);
  static final Paint _fallbackMine = Paint()..color = const Color(0xFFFF4A3A);

  void drawFallback(Canvas canvas, int sprite, double cx, double cy, double r) {
    canvas.save();
    canvas.translate(cx, cy);
    if (sprite < 8) {
      final p = _digits[sprite + 1];
      if (p != null) {
        final s = r * 1.25 / 32;
        canvas.scale(s, s);
        canvas.drawParagraph(p, Offset(-24, -p.height / 2));
      }
    } else if (sprite == Sprite.flag || sprite == Sprite.flagWrong) {
      canvas.drawCircle(Offset.zero, r * 0.35, _fallbackFlag);
    } else {
      canvas.drawCircle(Offset.zero, r * 0.35, _fallbackMine);
    }
    canvas.restore();
  }

  void dispose() {
    _disposed = true;
    atlas?.dispose();
    atlas = null;
    for (final p in _digits.values) {
      p.dispose();
    }
    _digits.clear();
  }
}
