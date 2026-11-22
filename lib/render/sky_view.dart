import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/planet/planet_environment.dart';
import 'globe_controller.dart';
import 'sky_assets.dart';

/// Which pieces of the art pack a world's sky uses.
class SkyRecipe {
  const SkyRecipe({
    required this.nebula,
    required this.giant,
    required this.ring,
    required this.stars,
    required this.giantPos,
    required this.giantSize,
    required this.giantTilt,
    required this.spinSpeed,
  });

  final int nebula; // 0-based
  final int giant; // 0-based
  final int? ring; // 0-based or none
  final int stars;
  final Offset giantPos; // fraction of the screen
  final double giantSize; // fraction of the shorter side (radius)
  final double giantTilt; // radians
  final double spinSpeed; // texture widths per second

  static SkyRecipe forWorld(PlanetEnvironment env, int seed) {
    // A little seeded variety so two worlds of one type are not identical.
    final h = (seed * 2654435761) & 0xFFFFFFFF;
    final left = (h & 1) == 0;
    final big = 0.12 + ((h >> 3) & 7) / 7 * 0.05;
    final y = 0.17 + ((h >> 6) & 7) / 7 * 0.10;
    final tilt = (((h >> 9) & 15) / 15 - 0.5) * 0.7;
    final (neb, giant, ring) = switch (env) {
      PlanetEnvironment.oceanic => (4, 1, 1),
      PlanetEnvironment.desert => (2, 0, null),
      PlanetEnvironment.frozen => (1, 3, 2),
      PlanetEnvironment.verdant => (0, 2, null),
      PlanetEnvironment.volcanic => (3, 0, 0),
      PlanetEnvironment.crystalline => (4, 3, null),
    };
    return SkyRecipe(
      nebula: neb,
      giant: giant % SkyAssets.giantCount,
      ring: ring,
      stars: (h >> 13) & 1,
      giantPos: Offset(left ? 0.19 + ((h >> 14) & 3) * 0.015 : 0.81 - ((h >> 14) & 3) * 0.015, y),
      giantSize: big,
      giantTilt: tilt,
      spinSpeed: 0.0035 + ((h >> 16) & 3) * 0.001,
    );
  }
}

class _Shooter {
  _Shooter(this.start, this.duration, this.from, this.dir, this.length);
  final double start;
  final double duration;
  final Offset from; // fraction of screen
  final Offset dir; // unit
  final double length; // fraction of screen width
}

/// Animated space behind the globe. It owns its own ticker and repaint
/// boundary, so the planet's frame loop never has to redraw it.
class SkyView extends StatefulWidget {
  const SkyView({super.key, required this.controller});

  final GlobeController controller;

  @override
  State<SkyView> createState() => _SkyViewState();
}

class _SkyViewState extends State<SkyView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  late final _SkyPainter _painter;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _painter = _SkyPainter(widget.controller, _repaint);
    SkyAssets.load().then((_) {
      if (mounted) _repaint.value++;
    });
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration t) {
    final c = widget.controller;
    // ~30 fps is plenty for slow drift; static when calm/off.
    if (!c.animatedSky) return;
    final still = c.reducedMotion;
    if ((t - _last).inMilliseconds < (still ? 250 : 33)) return;
    _last = t;
    _painter.time = t.inMicroseconds / 1e6;
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _painter, size: Size.infinite),
        ),
      );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.c, Listenable repaint) : super(repaint: repaint);

  final GlobeController c;
  double time = 0;

  SkyRecipe? _recipe;
  PlanetEnvironment? _recipeEnv;
  int? _recipeSeed;

  final List<_Shooter> _shooters = [];
  double _nextShooter = 3;
  final math.Random _rng = math.Random(7);

  // Reusable giant-sphere mesh.
  static const int _lon = 28, _lat = 20;
  late final Float32List _gPos = Float32List((_lon + 1) * (_lat + 1) * 2);
  late final Float32List _gUv = Float32List((_lon + 1) * (_lat + 1) * 2);
  late final Uint16List _gIdx = _buildIndices();
  double _gPosR = -1;

  Uint16List _buildIndices() {
    final out = <int>[];
    for (var j = 0; j < _lat; j++) {
      for (var i = 0; i < _lon; i++) {
        final a = j * (_lon + 1) + i, b = a + 1, d = a + _lon + 1, e = d + 1;
        out.addAll([a, b, d, b, e, d]);
      }
    }
    return Uint16List.fromList(out);
  }

  void dispose() {}

  @override
  bool shouldRepaint(covariant _SkyPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    if (!c.skyActive) return;
    final env = c.appearance.environment;
    final seed = c.appearance.seed;
    if (_recipe == null || _recipeEnv != env || _recipeSeed != seed) {
      _recipe = SkyRecipe.forWorld(env, seed);
      _recipeEnv = env;
      _recipeSeed = seed;
    }
    final r = _recipe!;
    final calm = c.reducedMotion;
    final t = calm ? 0.0 : time;
    final atmo = c.appearance.style.atmosphere;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [Color(0xFF020611), Color(0xFF01030A)],
        ),
    );

    // Parallax from the camera's orientation: nearer layers move more.
    final m = c.camera.matrix;
    final yaw = math.atan2(m[2], m[8]);
    final pitch = math.asin(m[5].clamp(-1.0, 1.0).toDouble());
    final px = yaw * size.width * 0.045;
    final py = pitch * size.height * 0.045;

    _cover(canvas, size, SkyAssets.stars[r.stars], Offset(px * 0.6 + t * 1.1, py * 0.6), 1.12, BlendMode.plus, 0.85);
    _cover(
      canvas,
      size,
      SkyAssets.nebulae[r.nebula],
      Offset(px * 1.0 + math.sin(t * 0.04) * 6, py * 1.0 + math.cos(t * 0.033) * 4),
      1.18,
      BlendMode.plus,
      0.95,
      tint: Color.lerp(const Color(0xFFFFFFFF), atmo, 0.22),
    );
    _cover(canvas, size, SkyAssets.stars[1 - r.stars], Offset(px * 1.7 - t * 2.0, py * 1.7), 1.22, BlendMode.plus, 0.55);

    _giant(canvas, size, r, t, Offset(px * 1.35, py * 1.35));
    if (!calm) _shootingStars(canvas, size, t);
  }

  void _cover(Canvas canvas, Size size, ui.Image? img, Offset shift, double zoom, BlendMode mode, double alpha,
      {Color? tint}) {
    if (img == null) return;
    final iw = img.width.toDouble(), ih = img.height.toDouble();
    final s = math.max(size.width / iw, size.height / ih) * zoom;
    final w = iw * s, h = ih * s;
    final maxX = (w - size.width) / 2, maxY = (h - size.height) / 2;
    final dx = shift.dx.clamp(-maxX, maxX).toDouble();
    final dy = shift.dy.clamp(-maxY, maxY).toDouble();
    final dst = Rect.fromLTWH((size.width - w) / 2 + dx, (size.height - h) / 2 + dy, w, h);
    final p = Paint()
      ..blendMode = mode
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255);
    if (tint != null) p.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst, p);
  }

  void _giant(Canvas canvas, Size size, SkyRecipe r, double t, Offset shift) {
    final tex = SkyAssets.giants[r.giant];
    if (tex == null) return;
    final rad = math.min(size.width, size.height) * r.giantSize;
    final centre = Offset(size.width * r.giantPos.dx, size.height * r.giantPos.dy) + shift;
    final ringImg = r.ring == null ? null : SkyAssets.rings[r.ring!];

    final cv = canvas;
    void ringHalf(bool front) {
      if (ringImg == null) return;
      final tilt = SkyAssets.ringTilt[r.ring!];
      final w = rad * 2 * 2.25;
      final h = w * ringImg.height / ringImg.width;
      cv.save();
      cv.translate(centre.dx, centre.dy);
      cv.rotate(r.giantTilt * 0.35 + tilt);
      cv.clipRect(front ? Rect.fromLTRB(-w, 0, w, h) : Rect.fromLTRB(-w, -h, w, 0));
      cv.rotate(-tilt);
      cv.drawImageRect(
        ringImg,
        Rect.fromLTWH(0, 0, ringImg.width.toDouble(), ringImg.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = const Color(0xE6FFFFFF),
      );
      cv.restore();
    }

    ringHalf(false);
    _sphere(cv, tex, centre, rad, r, t);
    ringHalf(true);
  }

  void _sphere(Canvas canvas, ui.Image tex, Offset centre, double rad, SkyRecipe r, double t) {
    // Orthographic hemisphere: fixed positions, scrolling texture coordinates.
    if (_gPosR != rad) {
      var k = 0;
      for (var j = 0; j <= _lat; j++) {
        final la = -math.pi / 2 + math.pi * j / _lat;
        for (var i = 0; i <= _lon; i++) {
          final lo = -math.pi / 2 + math.pi * i / _lon;
          _gPos[k] = math.cos(la) * math.sin(lo) * rad;
          _gPos[k + 1] = -math.sin(la) * rad;
          k += 2;
        }
      }
      _gPosR = rad;
    }
    final tw = tex.width.toDouble(), th = tex.height.toDouble();
    final spin = t * r.spinSpeed;
    var k = 0;
    for (var j = 0; j <= _lat; j++) {
      final la = -math.pi / 2 + math.pi * j / _lat;
      final v = (0.5 - la / math.pi) * th;
      for (var i = 0; i <= _lon; i++) {
        final lo = -math.pi / 2 + math.pi * i / _lon;
        final u = ((lo / (2 * math.pi)) + 0.25 + spin) * tw;
        _gUv[k] = u;
        _gUv[k + 1] = v;
        k += 2;
      }
    }

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(r.giantTilt * 0.35);
    final shader = ui.ImageShader(tex, TileMode.repeated, TileMode.clamp, Matrix4.identity().storage,
        filterQuality: FilterQuality.medium);
    final verts = ui.Vertices.raw(ui.VertexMode.triangles, _gPos, textureCoordinates: _gUv, indices: _gIdx);
    canvas.drawVertices(verts, BlendMode.srcOver, Paint()..shader = shader);
    verts.dispose();
    shader.dispose();

    // Shading: limb darkening, a night side, and a thin atmosphere rim.
    final disc = Rect.fromCircle(center: Offset.zero, radius: rad);
    canvas.drawCircle(
      Offset.zero,
      rad,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(-rad * 0.38, -rad * 0.30),
          rad * 1.55,
          const [Color(0x00000000), Color(0x30000000), Color(0xE6000008)],
          const [0.0, 0.55, 1.0],
        ),
    );
    canvas.drawCircle(
      Offset.zero,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rad * 0.05
        ..shader = ui.Gradient.linear(
          disc.topLeft,
          disc.bottomRight,
          const [Color(0x66BFE4FF), Color(0x00BFE4FF)],
        ),
    );
    canvas.restore();
  }

  void _shootingStars(Canvas canvas, Size size, double t) {
    if (t >= _nextShooter) {
      final ang = 0.35 + _rng.nextDouble() * 0.5; // down and to the side
      final dir = Offset(_rng.nextBool() ? math.cos(ang) : -math.cos(ang), math.sin(ang));
      _shooters.add(_Shooter(
        t,
        0.55 + _rng.nextDouble() * 0.35,
        Offset(0.1 + _rng.nextDouble() * 0.8, _rng.nextDouble() * 0.45),
        dir,
        0.16 + _rng.nextDouble() * 0.12,
      ));
      _nextShooter = t + 4 + _rng.nextDouble() * 7;
    }
    _shooters.removeWhere((s) => t - s.start > s.duration);
    for (final s in _shooters) {
      final p = (t - s.start) / s.duration;
      final head = Offset(
        (s.from.dx + s.dir.dx * s.length * 2.2 * p) * size.width,
        (s.from.dy + s.dir.dy * s.length * 2.2 * p) * size.width,
      );
      final tail = head - Offset(s.dir.dx, s.dir.dy) * (s.length * size.width) * math.min(1.0, p * 3);
      final a = math.sin(p * math.pi).clamp(0.0, 1.0).toDouble();
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(
            tail,
            head,
            [const Color(0x00FFFFFF), Color.fromARGB((235 * a).round(), 235, 245, 255)],
          ),
      );
      canvas.drawCircle(head, 2.2, Paint()..color = Color.fromARGB((255 * a).round(), 255, 255, 255));
    }
  }
}
