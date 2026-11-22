import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/game/game_engine.dart';
import '../core/planet/planet_environment.dart';
import '../theme/hexfall_theme.dart';
import 'globe_controller.dart';

/// Paints the space backdrop, atmosphere, planet body and the tile mesh.
class GlobePainter extends CustomPainter {
  GlobePainter(this.controller)
      : super(repaint: Listenable.merge([controller, controller.frame]));

  final GlobeController controller;

  // Cached star field (normalised coordinates), scaled per size.
  static final Float32List _starsNorm = _makeStars(260, 7);
  Size? _cachedSize;
  Float32List? _starsScaled;
  Float32List? _bigStarsScaled;

  static Float32List _makeStars(int count, int seed) {
    final rnd = math.Random(seed);
    final out = Float32List(count * 2);
    for (var i = 0; i < count; i++) {
      out[i * 2] = rnd.nextDouble();
      out[i * 2 + 1] = rnd.nextDouble();
    }
    return out;
  }

  void _scaleStars(Size size) {
    if (_cachedSize == size) return;
    _cachedSize = size;
    final small = <double>[];
    final big = <double>[];
    for (var i = 0; i < _starsNorm.length ~/ 2; i++) {
      final x = _starsNorm[i * 2] * size.width;
      final y = _starsNorm[i * 2 + 1] * size.height;
      (i % 7 == 0 ? big : small)
        ..add(x)
        ..add(y);
    }
    _starsScaled = Float32List.fromList(small);
    _bigStarsScaled = Float32List.fromList(big);
  }

  // --- Cached static layers (recorded once, replayed every frame) ----------------

  ui.Picture? _bgPic;
  Size? _bgSize;
  Color? _bgAtmo;
  ui.Picture? _basePic;
  Object? _baseKey;
  ui.Picture? _rimPic;
  Object? _rimKey;

  ui.Picture _record(void Function(Canvas c) draw) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec));
    return rec.endRecording();
  }

  void disposeLayers() {
    _bgPic?.dispose();
    _basePic?.dispose();
    _rimPic?.dispose();
    _bgPic = _basePic = _rimPic = null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final c = controller;
    final cam = c.camera;
    final proj = cam.projection(size);
    final center = Offset(proj.cx, proj.cy);
    final radius = proj.radiusPx;
    final t = c.time;
    final calm = c.reducedMotion;
    final atmo = c.appearance.style.atmosphere;

    canvas.save();
    // Screen shake after the fatal explosion (never in reduced-motion mode).
    final shakeAmp = c.shakeAmplitude;
    if (!calm && shakeAmp > 0.05) {
      canvas.translate(math.sin(t * 91) * shakeAmp, math.cos(t * 77) * shakeAmp);
    }

    // Space, nebulae, stars and the ringed giant.
    if (_bgPic == null || _bgSize != size || _bgAtmo != atmo) {
      _bgPic?.dispose();
      _bgPic = _record((cv) => _recordBackdrop(cv, size, atmo));
      _bgSize = size;
      _bgAtmo = atmo;
    }
    canvas.drawPicture(_bgPic!);

    // Atmosphere halo, hologram base rings and the dark planet body.
    final radiusKey = (radius * 2).round() / 2;
    final baseKey = Object.hash(size, radiusKey, atmo);
    if (_basePic == null || _baseKey != baseKey) {
      _basePic?.dispose();
      _basePic = _record((cv) => _recordPlanetBase(cv, center, radius, atmo));
      _baseKey = baseKey;
    }
    canvas.drawPicture(_basePic!);

    // The tile mesh.
    c.renderer.paint(canvas, size, cam, c.renderOptions());

    // Rim light over the limb to hide the faceted silhouette.
    if (_rimPic == null || _rimKey != baseKey) {
      _rimPic?.dispose();
      _rimPic = _record((cv) => _recordRim(cv, center, radius, atmo));
      _rimKey = baseKey;
    }
    canvas.drawPicture(_rimPic!);

    _paintAnomaly(canvas, center, radius, t, calm);
    _paintShield(canvas, center, radius, t, calm);
    _paintExplosions(canvas, center, radius, t, calm);
    _paintVictory(canvas, center, radius, t, calm);
    canvas.restore();

    _paintHoldMenu(canvas, size);

    // Red screen flash on a mine hit (softened in reduced-motion mode).
    final hitAge = t - c.hitFlashStart;
    if (hitAge >= 0 && hitAge < 0.5) {
      final a = (1 - hitAge / 0.5) * (calm ? 0.10 : 0.30);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 60, 40, a),
      );
    }
  }

  void _recordPlanetBase(Canvas canvas, Offset center, double radius, Color atmo) {
    // Atmosphere halo.
    canvas.drawCircle(
      center,
      radius * 1.42,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius * 1.42,
          [atmo.withAlpha(0), atmo.withAlpha(0), atmo.withAlpha(0x70), atmo.withAlpha(0x22), atmo.withAlpha(0)],
          const [0.0, 0.69, 0.72, 0.84, 1.0],
        ),
    );

    // Hologram projector rings under the planet, as in the concept art.
    final ringCenter = Offset(center.dx, center.dy + radius * 1.18);
    for (var i = 0; i < 4; i++) {
      final k = 1.0 + i * 0.26;
      final rect = Rect.fromCenter(center: ringCenter, width: radius * 2 * k * 1.05, height: radius * 2 * k * 0.17);
      if (i == 0) {
        canvas.save();
        canvas.translate(ringCenter.dx, ringCenter.dy);
        canvas.scale(1, 0.17);
        canvas.drawCircle(
          Offset.zero,
          radius * k * 1.05,
          Paint()
            ..shader = ui.Gradient.radial(
              Offset.zero,
              radius * k * 1.05,
              [HexfallTheme.cyan.withAlpha(46), HexfallTheme.cyan.withAlpha(0)],
              const [0.2, 1.0],
            ),
        );
        canvas.restore();
      }
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2.0 : 1.2
          ..color = HexfallTheme.cyan.withAlpha(110 - i * 22),
      );
    }
    // Short tick marks on the outer ring.
    final outer = Rect.fromCenter(center: ringCenter, width: radius * 2 * 1.78 * 1.05, height: radius * 2 * 1.78 * 0.17);
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final rx = outer.width / 2, ry = outer.height / 2;
      final p0 = Offset(ringCenter.dx + math.cos(a) * rx, ringCenter.dy + math.sin(a) * ry);
      final p1 = Offset(ringCenter.dx + math.cos(a) * (rx + 7), ringCenter.dy + math.sin(a) * (ry + 2));
      canvas.drawLine(p0, p1, Paint()..strokeWidth = 1.2..color = HexfallTheme.cyan.withAlpha(70));
    }

    // Dark planet body: shows through the gaps between tiles.
    canvas.drawCircle(
      center,
      radius * 0.995,
      Paint()
        ..shader = ui.Gradient.radial(
          center + Offset(-radius * 0.30, -radius * 0.38),
          radius * 1.35,
          [
            Color.lerp(const Color(0xFF0A1C30), atmo, 0.30)!,
            Color.lerp(const Color(0xFF03060C), atmo, 0.10)!,
          ],
        ),
    );
  }

  void _recordRim(Canvas canvas, Offset center, double radius, Color atmo) {
    canvas.drawCircle(
      center,
      radius * 1.06,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius * 1.06,
          [atmo.withAlpha(0), atmo.withAlpha(0), atmo.withAlpha(0x66), atmo.withAlpha(0)],
          const [0.0, 0.90, 0.985, 1.0],
        ),
    );
  }

  void _paintHoldMenu(Canvas canvas, Size size) {
    final m = controller.holdMenu;
    if (m == null) return;
    final calm = controller.reducedMotion;
    final k = calm ? 1.0 : ((controller.time - m.start) / 0.12).clamp(0.0, 1.0).toDouble();

    // Ring around the held tile and faint guide line through both options.
    canvas.drawCircle(
      m.anchor,
      m.cellRadius * 1.18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withAlpha(230),
    );
    final hasFlag = m.kind != HoldMenuKind.number;
    final top = Offset(m.anchor.dx, m.anchor.dy - m.distance * k);
    final bottom = Offset(m.anchor.dx, m.anchor.dy + m.distance * k);
    canvas.drawLine(
      hasFlag ? bottom : m.anchor,
      top,
      Paint()
        ..strokeWidth = 1.5
        ..color = HexfallTheme.cyan.withAlpha(90),
    );

    _pill(canvas, size, top, m.kind == HoldMenuKind.number ? 'CHORD' : 'REVEAL', true, m.highlight == -1, HexfallTheme.cyan);
    if (hasFlag) {
      _pill(canvas, size, bottom, m.kind == HoldMenuKind.flagged ? 'UNFLAG' : 'FLAG', false, m.highlight == 1, HexfallTheme.amber);
    }
  }

  void _pill(Canvas canvas, Size size, Offset center, String text, bool up, bool active, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: active ? HexfallTheme.spaceBlack : color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const arrow = 8.0;
    final w = tp.width + 26 + arrow * 2;
    final h = tp.height + 16;
    final cx = center.dx.clamp(w / 2 + 6, size.width - w / 2 - 6).toDouble();
    final cy = center.dy.clamp(h / 2 + 6, size.height - h / 2 - 6).toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      Radius.circular(h / 2),
    );
    if (active) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withAlpha(120)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawRRect(rect, Paint()..color = active ? color : const Color(0xEB0A1626));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );
    // Direction arrow drawn as a path (no font dependency).
    final ax = rect.left + 18;
    final path = Path();
    if (up) {
      path
        ..moveTo(ax, cy - arrow / 2)
        ..lineTo(ax - arrow / 2 - 1, cy + arrow / 2)
        ..lineTo(ax + arrow / 2 + 1, cy + arrow / 2);
    } else {
      path
        ..moveTo(ax, cy + arrow / 2)
        ..lineTo(ax - arrow / 2 - 1, cy - arrow / 2)
        ..lineTo(ax + arrow / 2 + 1, cy - arrow / 2);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = active ? HexfallTheme.spaceBlack : color);
    tp.paint(canvas, Offset(rect.left + 30 + arrow, cy - tp.height / 2));
    tp.dispose();
  }

  void _paintAnomaly(Canvas canvas, Offset center, double radius, double t, bool calm) {
    final c = controller;
    if (!c.anomalyEffects || c.anomaly == PlanetAnomaly.none) return;
    final tint = c.anomaly.tint;
    var alpha = 0.07;
    if (!calm) {
      switch (c.anomaly) {
        case PlanetAnomaly.ionFog:
          alpha = 0.10 + 0.05 * math.sin(t * 0.7);
        case PlanetAnomaly.electromagneticStorm:
          // Brief flashes, kept dim so numbers always stay readable.
          final f = math.pow(math.max(0.0, math.sin(t * 1.3 + math.sin(t * 0.37) * 2)), 24).toDouble();
          alpha = 0.05 + 0.13 * f;
        case PlanetAnomaly.seismicActivity:
          alpha = 0.06 + 0.04 * math.sin(t * 2.2);
        case PlanetAnomaly.crystalResonance:
          alpha = 0.07 + 0.04 * math.sin(t * 1.1);
        case PlanetAnomaly.none:
          break;
      }
    }
    // A haze around the limb only: the middle of the planet stays clear.
    canvas.drawCircle(
      center,
      radius * 1.04,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius * 1.04,
          [tint.withAlpha(0), tint.withAlpha((alpha * 255).round())],
          const [0.55, 1.0],
        ),
    );
  }

  void _paintShield(Canvas canvas, Offset center, double radius, double t, bool calm) {
    final c = controller;
    final e = c.engine;
    // Faint standing shield bubble while the shield is available.
    if (e != null && e.shieldAvailable && e.status == GameStatus.playing) {
      canvas.drawCircle(
        center,
        radius * 1.05,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = HexfallTheme.cyan.withAlpha(calm ? 50 : (40 + 25 * math.sin(t * 2)).round()),
      );
    }
    final age = t - c.shieldPulseStart;
    if (age >= 0 && age < 1.4) {
      final k = age / 1.4;
      final r = radius * (1.02 + 0.30 * (calm ? 0.0 : k));
      final a = (1 - k);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            r,
            [
              HexfallTheme.cyan.withAlpha(0),
              HexfallTheme.cyan.withAlpha((90 * a).round()),
              HexfallTheme.cyan.withAlpha((230 * a).round()),
            ],
            const [0.0, 0.82, 1.0],
          ),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 5 * a
          ..color = Colors.white.withAlpha((220 * a).round()),
      );
    }
  }

  void _paintExplosions(Canvas canvas, Offset center, double radius, double t, bool calm) {
    final c = controller;
    for (final x in c.explosions) {
      final age = t - x.start;
      if (age < 0 || age > 1.0) continue;
      final pos = c.renderer.cellScreenPosition(x.cell);
      if (pos == null) continue;
      final k = age / 1.0;
      final base = math.max(10.0, c.renderer.cellScreenRadius(x.cell));
      final r = base * (1.0 + 3.2 * k);
      final a = 1 - k;
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            pos,
            r,
            [
              Color.fromRGBO(255, 245, 200, calm ? 0.5 * a : 0.95 * a),
              Color.fromRGBO(255, 120, 30, 0.75 * a),
              const Color(0x00FF3000),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );
      if (!calm) {
        canvas.drawCircle(
          pos,
          r * 1.25,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * a + 0.5
            ..color = Color.fromRGBO(255, 190, 120, 0.8 * a),
        );
      }
    }
  }

  void _paintVictory(Canvas canvas, Offset center, double radius, double t, bool calm) {
    final age = t - controller.victoryStart;
    if (age < 0 || age > 6.0) return;
    final pulse = calm ? 0.5 : 0.5 + 0.5 * math.sin(age * 3.0);
    final fade = age < 5.0 ? 1.0 : (6.0 - age);
    canvas.drawCircle(
      center,
      radius * 1.12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 2 * pulse
        ..color = HexfallTheme.good.withAlpha((120 * fade * (0.5 + 0.5 * pulse)).round()),
    );
  }

  void _recordBackdrop(Canvas canvas, Size size, Color atmo) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [HexfallTheme.spaceDeep, HexfallTheme.spaceBlack],
        ),
    );
    // Nebulae.
    final longest = math.max(size.width, size.height);
    void nebula(double fx, double fy, double fr, Color c) {
      final o = Offset(size.width * fx, size.height * fy);
      canvas.drawCircle(o, longest * fr, Paint()..shader = ui.Gradient.radial(o, longest * fr, [c, c.withAlpha(0)]));
    }

    // Each world tints the sky: nebulae pick up the atmosphere colour.
    Color sky(Color c, double k) => Color.lerp(c, atmo.withAlpha(c.alpha), k)!;
    nebula(0.16, 0.24, 0.46, sky(const Color(0x3A2A8CC8), 0.85));
    nebula(0.86, 0.82, 0.52, sky(const Color(0x2E6A3CC8), 0.50));
    nebula(0.45, 0.95, 0.40, sky(const Color(0x24C86A3C), 0.35));
    nebula(0.70, 0.30, 0.30, sky(const Color(0x1E2AC8A8), 0.75));

    // Stars.
    _scaleStars(size);
    canvas.drawRawPoints(
      ui.PointMode.points,
      _starsScaled!,
      Paint()
        ..color = const Color(0x99CFE8FF)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRawPoints(
      ui.PointMode.points,
      _bigStarsScaled!,
      Paint()
        ..color = const Color(0xDDFFFFFF)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // Distant ringed gas giant (top right), as in the concept art.
    final gr = math.min(size.width, size.height) * 0.17;
    final gc = Offset(size.width * 0.86, size.height * 0.20);
    void ring(bool front) {
      canvas.save();
      canvas.translate(gc.dx, gc.dy);
      canvas.rotate(-0.30);
      canvas.scale(1, 0.26);
      const widths = [0.10, 0.05, 0.14, 0.04, 0.08, 0.03];
      const radii = [1.55, 1.78, 2.0, 2.3, 2.6, 2.95];
      const alphas = [150, 90, 130, 70, 90, 50];
      for (var i = 0; i < 6; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: gr * radii[i]),
          front ? 0 : math.pi,
          math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = gr * widths[i]
            ..color = Color.fromARGB(alphas[i], 210, 200, 180),
        );
      }
      canvas.restore();
    }

    ring(false);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: gc, radius: gr)));
    const bands = [
      Color(0xFFD9C9A8), Color(0xFFB89B72), Color(0xFFE6D8B8), Color(0xFFA9845A),
      Color(0xFFD2BC92), Color(0xFF8E6C4A), Color(0xFFC9B085),
    ];
    for (var i = 0; i < bands.length; i++) {
      final y0 = gc.dy - gr + (2 * gr) * i / bands.length;
      canvas.drawRect(Rect.fromLTRB(gc.dx - gr, y0, gc.dx + gr, y0 + 2 * gr / bands.length + 1), Paint()..color = bands[i]);
    }
    canvas.drawCircle(
      gc,
      gr,
      Paint()
        ..shader = ui.Gradient.radial(
          gc + Offset(-gr * 0.35, -gr * 0.35),
          gr * 1.5,
          const [Color(0x00000000), Color(0xCC02060E)],
          const [0.35, 1.0],
        ),
    );
    canvas.restore();
    ring(true);
  }

  @override
  bool shouldRepaint(covariant GlobePainter oldDelegate) =>
      oldDelegate.controller != controller;
}
