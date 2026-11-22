import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/game/game_engine.dart';
import '../core/geometry/geodesic_grid.dart';
import '../theme/hexfall_theme.dart';
import 'globe_camera.dart';
import 'glyph_cache.dart';
import 'tile_atlas.dart';

/// Per-frame values the renderer needs that are not part of the grid itself.
class GlobeRenderOptions {
  const GlobeRenderOptions({
    required this.selected,
    required this.hovered,
    required this.marked,
    required this.time,
    required this.scanEffect,
    required this.quality,
    this.shown,
    this.counts,
    this.incorrect,
    this.glyphs,
    this.flashStart,
    this.flashKind,
    this.destruct = 0,
    this.outlineColor,
    this.pulseX = 0,
    this.pulseY = 0,
    this.pulseZ = 1,
    this.pulseFront = -1,
    this.pulseStrength = 0,
    this.numberColors,
    this.tint,
    this.terrain,
    this.terrainStrength = 1.0,
    this.scannedStrength = 0.6,
    this.walls = true,
    this.edges = true,
    this.relief = true,
  });

  final int selected;
  final int hovered;
  final Set<int> marked;
  final double time;
  final bool scanEffect;

  /// 0 = low, 1 = medium, 2 = high. Controls outline glow and dim outlines.
  final int quality;

  /// Visual cell state ([CellCode]) – null outside a game.
  final Uint8List? shown;

  /// Adjacent mine counts for revealed cells (null outside a game).
  final Uint8List? counts;

  /// 1 where a flag is wrong (only set after a loss).
  final Uint8List? incorrect;
  final GlyphCache? glyphs;

  /// Time each cell's flash began (seconds) and its colour kind
  /// (0 cyan, 1 red, 2 green).
  final Float32List? flashStart;
  final Uint8List? flashKind;

  /// Planet "shock" amount, 0 = at rest. Tiles are pushed outward by it.
  final double destruct;
  final Color? outlineColor;

  /// Reveal pulse: a bright ring travelling over the surface away from
  /// ([pulseX], [pulseY], [pulseZ]); [pulseFront] is its angular radius.
  final double pulseX;
  final double pulseY;
  final double pulseZ;
  final double pulseFront;
  final double pulseStrength;

  /// ARGB colour per mine count (index 1..8), used for tile outlines.
  final List<int>? numberColors;

  /// Planet colour lightly blended into the metal plates so every world's
  /// hardware reads slightly differently (null = neutral).
  final Color? tint;

  /// Terrain colour of every cell (rgb 0..1, 3 floats per cell). Tints the
  /// hidden plates so each planet keeps its own look.
  final Float32List? terrain;

  /// How strongly the terrain colours hidden plates (0 = plain metal).
  final double terrainStrength;

  /// Same for scanned (revealed) plates.
  final double scannedStrength;

  /// Depth effects (see Settings): raised tile sides, sun-facing edge glints,
  /// baked relief plates.
  final bool walls;
  final bool edges;
  final bool relief;
}

/// Accumulates soft-edged line "ribbons" (a 3-vertex-wide strip whose centre is
/// opaque and whose edges fade to transparent) and draws them as triangles.
/// This replaces stroked lines: it is anti-aliased, glows for free, and is far
/// cheaper than thousands of wide round-capped strokes.
class _RibbonBatch {
  _RibbonBatch(this.capacity)
      : _pos = Float32List(capacity * 2),
        _col = Int32List(capacity),
        _idx = Uint16List(capacity * 2);

  final int capacity;
  final Float32List _pos;
  final Int32List _col;
  final Uint16List _idx;
  int _v = 0;
  int _i = 0;
  Canvas? canvas;
  final Paint _paint = Paint();

  void addEdge(double ax, double ay, double bx, double by, double w, int argb) {
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.4) return;
    if (_v + 6 > capacity) flush();
    final nx = -dy / len * w, ny = dx / len * w;
    final edge = argb & 0x00FFFFFF;
    final b = _v;
    _set(b, ax + nx, ay + ny, edge);
    _set(b + 1, ax, ay, argb);
    _set(b + 2, ax - nx, ay - ny, edge);
    _set(b + 3, bx + nx, by + ny, edge);
    _set(b + 4, bx, by, argb);
    _set(b + 5, bx - nx, by - ny, edge);
    _idx[_i++] = b;
    _idx[_i++] = b + 1;
    _idx[_i++] = b + 4;
    _idx[_i++] = b;
    _idx[_i++] = b + 4;
    _idx[_i++] = b + 3;
    _idx[_i++] = b + 1;
    _idx[_i++] = b + 2;
    _idx[_i++] = b + 5;
    _idx[_i++] = b + 1;
    _idx[_i++] = b + 5;
    _idx[_i++] = b + 4;
    _v += 6;
  }

  void _set(int v, double x, double y, int c) {
    _pos[v * 2] = x;
    _pos[v * 2 + 1] = y;
    _col[v] = c;
  }

  void flush() {
    if (_v == 0) return;
    final c = canvas;
    if (c != null) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_pos, 0, _v * 2),
        colors: Int32List.sublistView(_col, 0, _v),
        indices: Uint16List.sublistView(_idx, 0, _i),
      );
      c.drawVertices(vertices, BlendMode.src, _paint);
      vertices.dispose();
    }
    _v = 0;
    _i = 0;
  }
}

/// Quads for the raised sides of tiles near the limb: a dark-steel gradient
/// from the tile top down to the planet body.
class _WallBatch {
  _WallBatch(this.capacity)
      : _pos = Float32List(capacity * 2),
        _col = Int32List(capacity),
        _idx = Uint16List(capacity ~/ 4 * 6);

  final int capacity;
  final Float32List _pos;
  final Int32List _col;
  final Uint16List _idx;
  int _v = 0;
  int _i = 0;
  Canvas? canvas;
  final Paint _paint = Paint();

  void addQuad(double ax, double ay, double bx, double by, double b2x, double b2y, double a2x, double a2y, int top, int bottom) {
    if (_v + 4 > capacity) flush();
    final b = _v;
    _set(b, ax, ay, top);
    _set(b + 1, bx, by, top);
    _set(b + 2, b2x, b2y, bottom);
    _set(b + 3, a2x, a2y, bottom);
    _idx[_i++] = b;
    _idx[_i++] = b + 1;
    _idx[_i++] = b + 2;
    _idx[_i++] = b;
    _idx[_i++] = b + 2;
    _idx[_i++] = b + 3;
    _v += 4;
  }

  void _set(int v, double x, double y, int c) {
    _pos[v * 2] = x;
    _pos[v * 2 + 1] = y;
    _col[v] = c;
  }

  void flush() {
    if (_v == 0) return;
    final c = canvas;
    if (c != null) {
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_pos, 0, _v * 2),
        colors: Int32List.sublistView(_col, 0, _v),
        indices: Uint16List.sublistView(_idx, 0, _i),
      );
      c.drawVertices(vertices, BlendMode.src, _paint);
      vertices.dispose();
    }
    _v = 0;
    _i = 0;
  }
}

/// Draws a [GeodesicGrid] as batched meshes.
///
/// A software 3D pipeline feeding `Canvas.drawVertices`: every frame the
/// visible cells' corners are rotated + projected into preallocated typed
/// lists, shaded per vertex (Lambert + fresnel rim + scan band + flashes +
/// reveal pulse) and submitted as one indexed triangle batch. Outlines are
/// soft triangle ribbons (also batched), glyphs come from a sprite atlas drawn
/// in a single call. No widgets per tile and no allocation per tile. Because
/// the planet is convex, back-face culling is exact and no depth sorting is
/// needed.
class GlobeRenderer {
  GlobeRenderer(this.grid) {
    final corners = grid.cellVertexIndices.length;
    final cells = grid.cellCount;

    // Pre-shrunk cell corners (planet space) so tiles show a gap between them.
    _inset = Float64List(corners * 3);
    for (var c = 0; c < cells; c++) {
      final cx = grid.centers[c * 3], cy = grid.centers[c * 3 + 1], cz = grid.centers[c * 3 + 2];
      for (var k = grid.cellOffsets[c]; k < grid.cellOffsets[c + 1]; k++) {
        final d = grid.cellVertexIndices[k] * 3;
        var x = cx + (grid.dualVertices[d] - cx) * HexfallTheme.tileInset;
        var y = cy + (grid.dualVertices[d + 1] - cy) * HexfallTheme.tileInset;
        var z = cz + (grid.dualVertices[d + 2] - cz) * HexfallTheme.tileInset;
        final l = math.sqrt(x * x + y * y + z * z);
        x /= l;
        y /= l;
        z /= l;
        _inset[k * 3] = x;
        _inset[k * 3 + 1] = y;
        _inset[k * 3 + 2] = z;
      }
    }

    cellRgb = Float32List(cells * 3);
    _kick = Float32List(cells);
    var seed = 0x2F6E2B1;
    for (var c = 0; c < cells; c++) {
      seed = (seed * 48271) % 2147483647;
      _kick[c] = 0.3 + 0.7 * (seed / 2147483647.0);
    }
    _cenX = Float32List(cells);
    _cenY = Float32List(cells);
    _cenR = Float32List(cells);
    _facing = Float32List(cells);
    _visible = Uint8List(cells);
    _screen = Float32List(corners * 2);
    final maxVerts = cells + corners; // one centre + one vertex per corner
    _pos = Float32List(maxVerts * 2);
    _col = Int32List(maxVerts);
    _idx = Uint16List(corners * 3);
    _atT = Float32List(cells * 4);
    _atR = Float32List(cells * 4);
    _uv = Float32List(maxVerts * 2);
    _colAdd = Int32List(maxVerts);
    // Plate texture offsets (relative to the plate centre) for 6 / 5 corners.
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3;
      _uvDx6[k] = TileAtlas.hexRadius * math.cos(a);
      _uvDy6[k] = -TileAtlas.hexRadius * math.sin(a);
    }
    for (var k = 0; k < 5; k++) {
      // Pentagon plates have their apex pointing up.
      final a = math.pi / 2 + k * 2 * math.pi / 5;
      _uvDx5[k] = TileAtlas.hexRadius * math.cos(a);
      _uvDy5[k] = -TileAtlas.hexRadius * math.sin(a);
    }
  }

  final GeodesicGrid grid;

  /// Base colour of every cell (rgb 0..1, 3 floats per cell). Written by the
  /// controller; read every frame.
  late final Float32List cellRgb;

  late final Float64List _inset;
  late final Uint8List _visible;
  late final Float32List _screen;
  late final Float32List _pos;
  late final Int32List _col;
  late final Uint16List _idx;
  late final Float32List _kick;
  late final Float32List _cenX;
  late final Float32List _cenY;
  late final Float32List _cenR;
  late final Float32List _facing;
  late final Float32List _atT;
  late final Float32List _atR;
  late final Float32List _uv;
  late final Int32List _colAdd;
  final Float32List _uvDx6 = Float32List(6);
  final Float32List _uvDy6 = Float32List(6);
  final Float32List _uvDx5 = Float32List(5);
  final Float32List _uvDy5 = Float32List(5);

  final _RibbonBatch _glow = _RibbonBatch(60000);
  final _RibbonBatch _core = _RibbonBatch(60000);
  final _RibbonBatch _hi = _RibbonBatch(60000);
  final _WallBatch _wall = _WallBatch(60000);
  final Paint _meshPaint = Paint();
  final Paint _texPaint = Paint();
  final Paint _addPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.medium;

  /// Diagnostics from the last frame.
  int visibleCells = 0;
  double lastPaintMs = 0;

  // Per-frame constants (fields so the vertex helper stays cheap to call).
  final Float32List _wallX = Float32List(8);
  final Float32List _wallY = Float32List(8);
  late Float64List _m;
  double _d = 3.4, _cx = 0, _cy = 0, _f = 1;
  double _lx = 0, _ly = 0, _lz = 1;
  bool _scan = false;
  double _scanY = 0;
  double _flash = 0, _fR = 0, _fG = 0, _fB = 0;
  double _pu = 0;
  double _vb = 0; // per-vertex bevel multiplier for the current vertex
  double _bevel = 0;
  bool _tex = false; // textured plate mode for this frame
  double _lf = 0.4; // lighting floor for the current cell (plates)
  double _tr = 1, _tg = 1, _tb = 1; // plate tint of the current cell
  double _ar = 1, _ag = 1, _ab = 1; // planet (atmosphere) tint for the frame
  double _hr = 0, _hg = 0, _hb = 0; // additive terrain haze of the current cell
  double _aR = 0.42, _aG = 0.62, _aB = 0.78; // atmosphere colour 0..1

  bool _texLast = false;

  final Stopwatch _watch = Stopwatch();

  static const double _scanWidth = 0.014;
  static const double _flashDuration = 0.9;
  static const double _pulseWidth = 0.15;

  void paint(Canvas canvas, Size size, GlobeCamera cam, GlobeRenderOptions o) {
    _watch
      ..reset()
      ..start();

    final proj = cam.projection(size);
    _m = cam.matrix;
    _d = proj.distance;
    _cx = proj.cx;
    _cy = proj.cy;
    _f = proj.focal;

    const ll = HexfallTheme.lightDirection;
    final len = math.sqrt(ll[0] * ll[0] + ll[1] * ll[1] + ll[2] * ll[2]);
    _lx = ll[0] / len;
    _ly = ll[1] / len;
    _lz = ll[2] / len;

    _scan = o.scanEffect;
    _scanY = ((o.time * 0.28) % 1.0) * 2.8 - 1.4;

    _glow.canvas = canvas;
    _core.canvas = canvas;
    _hi.canvas = canvas;
    _wall.canvas = canvas;

    // Textured plates need the artwork and an in-game state to pick plates from.
    _tex = TileAtlas.ready && o.shown != null;
    _texLast = _tex;
    final tint = o.tint;
    if (tint != null) {
      final mx = math.max(1, math.max(tint.red, math.max(tint.green, tint.blue))).toDouble();
      _ar = 0.80 + 0.20 * tint.red / mx;
      _ag = 0.80 + 0.20 * tint.green / mx;
      _ab = 0.80 + 0.20 * tint.blue / mx;
      _aR = tint.red / 255.0;
      _aG = tint.green / 255.0;
      _aB = tint.blue / 255.0;
    } else {
      _ar = _ag = _ab = 1;
      _aR = 0.42;
      _aG = 0.62;
      _aB = 0.78;
    }
    final terrain = o.terrain;

    final m = _m;
    // Camera position in planet space = D * third row of the matrix.
    final ox = _d * m[6], oy = _d * m[7], oz = _d * m[8];

    final centers = grid.centers;
    final offs = grid.cellOffsets;
    final cellCount = grid.cellCount;
    final shownList = o.shown;
    final hasPulse = o.pulseStrength > 0;

    var vCount = 0;
    var iCount = 0;
    var visible = 0;

    // Outline colours (r, g, b 0..255) for bright and dim edges.
    final override = o.outlineColor;

    for (var c = 0; c < cellCount; c++) {
      final ci = c * 3;
      final px = centers[ci], py = centers[ci + 1], pz = centers[ci + 2];
      // A point p on the unit sphere faces a camera at O when p . O > 1.
      final cd = px * ox + py * oy + pz * oz;
      if (cd < 0.985) {
        _visible[c] = 0;
        continue;
      }
      _visible[c] = 1;
      visible++;
      final facing = cd / _d;

      // --- Per-cell effects -----------------------------------------------------
      _flash = 0;
      final fs = o.flashStart;
      if (fs != null) {
        final age = o.time - fs[c];
        if (age >= 0 && age < _flashDuration) {
          _flash = (1 - age / _flashDuration) * 1.1;
          final kind = o.flashKind == null ? 0 : o.flashKind![c];
          if (kind == 1) {
            _fR = 1.0;
            _fG = 0.30;
            _fB = 0.08;
          } else if (kind == 2) {
            _fR = 0.35;
            _fG = 1.0;
            _fB = 0.65;
          } else {
            _fR = 0.25;
            _fG = 0.90;
            _fB = 1.0;
          }
        }
      }
      _pu = 0;
      if (hasPulse) {
        final cp = (px * o.pulseX + py * o.pulseY + pz * o.pulseZ).clamp(-1.0, 1.0).toDouble();
        final dd = (math.acos(cp) - o.pulseFront) / _pulseWidth;
        if (dd > -3 && dd < 3) _pu = math.exp(-dd * dd) * o.pulseStrength;
      }

      // --- Height: hidden raised, revealed sunken, plus pop / pulse bumps -------
      var lift = c == o.selected ? 1.03 : 1.0;
      var dim = false;
      if (shownList != null) {
        final st = shownList[c];
        if (st == CellCode.revealed) {
          dim = true;
          if (c != o.selected) lift = 0.99;
        } else if ((st == CellCode.hidden || st == CellCode.flagged) && c != o.selected) {
          lift = 1.014;
        }
      }
      lift += _flash * _flash * 0.05 + _pu * 0.024;
      if (o.destruct > 0) lift += o.destruct * _kick[c];

      final r = cellRgb[ci], g = cellRgb[ci + 1], b = cellRgb[ci + 2];
      final start = offs[c];
      final end = offs[c + 1];
      final deg = end - start;

      // Hidden tiles get a pillowed look: bright centre, darker edges.
      _bevel = (shownList != null && !dim && !_tex) ? 0.30 : 0.0;
      var plate = 0;
      if (_tex) {
        plate = _plateIndex(shownList![c], o.counts == null ? 0 : o.counts![c],
            o.incorrect != null && o.incorrect![c] == 1);
        final hiddenPlate = plate == TileAtlas.hidden;
        _lf = hiddenPlate ? 0.44 : 0.66;
        // Planet identity: hidden plates take strong colour from the terrain
        // underneath (oceans, ice caps, lava, forests); scanned plates keep
        // their neon frames but get a faint terrain haze.
        _tr = _ar;
        _tg = _ag;
        _tb = _ab;
        _hr = _hg = _hb = 0;
        if (terrain != null) {
          final t0 = terrain[ci], t1 = terrain[ci + 1], t2 = terrain[ci + 2];
          final mxc = math.max(0.03, math.max(t0, math.max(t1, t2)));
          final k = hiddenPlate ? o.terrainStrength : o.scannedStrength;
          var br = 0.46 + 0.80 * mxc;
          br = br > 1.0 ? 1.0 : br;
          if (!hiddenPlate) br = 1.0;
          _tr = math.max(0.0, (1 - k) + k * t0 / mxc) * br * _ar;
          _tg = math.max(0.0, (1 - k) + k * t1 / mxc) * br * _ag;
          _tb = math.max(0.0, (1 - k) + k * t2 / mxc) * br * _ab;
        }
        if (deg == 5) plate += TileAtlas.pentagonOffset;
      }
      final base = vCount;
      _vb = 1 + _bevel;
      _vertex(vCount++, px, py, pz, lift, r, g, b);
      _vb = 1 - 0.55 * _bevel;
      final ucx = TileAtlas.originX(plate) + TileAtlas.cell / 2;
      final ucy = TileAtlas.originY(plate) + TileAtlas.cell / 2;
      if (_tex) {
        _uv[base * 2] = ucx;
        _uv[base * 2 + 1] = ucy;
      }

      for (var k = 0; k < deg; k++) {
        final ii = (start + k) * 3;
        final vi = vCount++;
        _vertex(vi, _inset[ii], _inset[ii + 1], _inset[ii + 2], lift, r, g, b);
        _screen[(start + k) * 2] = _pos[vi * 2];
        _screen[(start + k) * 2 + 1] = _pos[vi * 2 + 1];
        if (_tex) {
          _uv[vi * 2] = ucx + (deg == 5 ? _uvDx5[k] : _uvDx6[k]);
          _uv[vi * 2 + 1] = ucy + (deg == 5 ? _uvDy5[k] : _uvDy6[k]);
        }
      }

      final ccx = _pos[base * 2], ccy = _pos[base * 2 + 1];
      _cenX[c] = ccx;
      _cenY[c] = ccy;
      // Mean corner distance: independent of which corner happens to be first,
      // so neighbouring glyphs always shrink together as cells turn away.
      var rSum = 0.0;
      for (var k = 0; k < deg; k++) {
        final dxr = _screen[(start + k) * 2] - ccx, dyr = _screen[(start + k) * 2 + 1] - ccy;
        rSum += math.sqrt(dxr * dxr + dyr * dyr);
      }
      _cenR[c] = rSum / deg;
      _facing[c] = facing;

      for (var k = 0; k < deg; k++) {
        _idx[iCount++] = base;
        _idx[iCount++] = base + 1 + k;
        _idx[iCount++] = base + 1 + (k + 1 == deg ? 0 : k + 1);
      }

      // --- Depth effects (hidden / flagged plates only) ---------------------------
      if (_tex && !dim && o.quality >= 1) {
        if (o.walls && facing < 0.86 && lift > 1.005) {
          _addWalls(start, deg, px, py, pz, lift, facing);
        }
        if (o.edges && facing > 0.12) {
          _addEdgeGlints(start, deg, ccx, ccy, facing);
        }
      }

      // --- Outline ribbons ------------------------------------------------------
      // The outline is the tile's "frame": dim on hidden tiles, glowing in the
      // number's colour on scanned tiles (like the concept art).
      double er, eg, eb, ca, cw, ga;
      if (shownList == null) {
        er = 0.27; eg = 0.85; eb = 1.0; ca = 0.80; cw = 1.6; ga = 0.17;
      } else {
        switch (shownList[c]) {
          case CellCode.revealed:
            final n = o.counts == null ? 0 : o.counts![c];
            final nc = o.numberColors;
            if (n > 0 && nc != null && n < nc.length) {
              final col = nc[n];
              er = (((col >> 16) & 0xFF) / 255.0) * 0.7 + 0.27 * 0.3;
              eg = (((col >> 8) & 0xFF) / 255.0) * 0.7 + 0.85 * 0.3;
              eb = ((col & 0xFF) / 255.0) * 0.7 + 1.0 * 0.3;
              ca = 0.95; cw = 1.9; ga = 0.34;
            } else {
              er = 0.15; eg = 0.55; eb = 0.62; ca = 0.35; cw = 1.1; ga = 0;
            }
          case CellCode.flagged:
            er = 0.30; eg = 0.70; eb = 1.0; ca = 0.90; cw = 1.8; ga = 0.30;
          case CellCode.mineRevealed:
            er = 1.0; eg = 0.30; eb = 0.20; ca = 0.95; cw = 1.8; ga = 0.32;
          case CellCode.exploded:
            er = 1.0; eg = 0.62; eb = 0.20; ca = 1.0; cw = 2.2; ga = 0.5;
          default: // hidden
            er = 0.21 + 0.5 * _aR; eg = 0.31 + 0.5 * _aG; eb = 0.39 + 0.5 * _aB;
            ca = 0.34; cw = 1.0; ga = 0;
        }
      }
      if (override != null && shownList == null) {
        er = override.red / 255.0;
        eg = override.green / 255.0;
        eb = override.blue / 255.0;
      }
      if (ca < 0.5 && o.quality == 0) continue; // low quality: skip faint outlines
      // Edges turn gold towards the limb, like the concept art.
      var t = (0.42 - facing) / 0.32;
      t = t < 0 ? 0 : (t > 1 ? 1 : t);
      er += (1.0 - er) * t;
      eg += (0.72 - eg) * t;
      eb += (0.25 - eb) * t;
      ca += 0.35 * t;
      ga += 0.10 * t;
      var fade = facing / 0.45;
      fade = fade > 1 ? 1 : fade;
      fade = 0.45 + 0.55 * fade;
      if (_tex) {
        // The plates carry their own glowing frames; keep only a soft rim line.
        ca *= 0.55;
        ga *= 0.6;
      }
      final coreArgb = _argb(ca * fade, er, eg, eb);
      final glowArgb = _argb(ga * fade, er, eg, eb);
      for (var k = 0; k < deg; k++) {
        final a = (start + k) * 2;
        final bIdx = (start + (k + 1 == deg ? 0 : k + 1)) * 2;
        final ax = _screen[a], ay = _screen[a + 1], bx = _screen[bIdx], by = _screen[bIdx + 1];
        if (ga > 0 && o.quality >= 2) _glow.addEdge(ax, ay, bx, by, 5.0, glowArgb);
        _core.addEdge(ax, ay, bx, by, cw, coreArgb);
      }
    }
    visibleCells = visible;

    // Walls first: neighbouring tops then cover them where they overlap, so a
    // wall only shows in the gaps and on steps, never as a slab over a tile.
    _wall.flush();
    if (vCount > 0) {
      if (_tex) {
        // Pass 1: plate texture x lighting. Pass 2: additive rim / scan / flash.
        _texPaint.shader = (o.relief && TileAtlas.reliefShader != null) ? TileAtlas.reliefShader : TileAtlas.shader;
        final lit = ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.sublistView(_pos, 0, vCount * 2),
          textureCoordinates: Float32List.sublistView(_uv, 0, vCount * 2),
          colors: Int32List.sublistView(_col, 0, vCount),
          indices: Uint16List.sublistView(_idx, 0, iCount),
        );
        canvas.drawVertices(lit, BlendMode.modulate, _texPaint);
        lit.dispose();
        final add = ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.sublistView(_pos, 0, vCount * 2),
          colors: Int32List.sublistView(_colAdd, 0, vCount),
          indices: Uint16List.sublistView(_idx, 0, iCount),
        );
        canvas.drawVertices(add, BlendMode.src, _addPaint);
        add.dispose();
      } else {
        final vertices = ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.sublistView(_pos, 0, vCount * 2),
          colors: Int32List.sublistView(_col, 0, vCount),
          indices: Uint16List.sublistView(_idx, 0, iCount),
        );
        canvas.drawVertices(vertices, BlendMode.src, _meshPaint);
        vertices.dispose();
      }
    }
    _glow.flush();
    _core.flush();
    _hi.flush();

    _paintGlyphs(canvas, o);
    _paintHighlights(canvas, o);

    _watch.stop();
    lastPaintMs = _watch.elapsedMicroseconds / 1000.0;
  }

  /// Raised sides of a tile: quads from the lifted top edge down to the planet
  /// body, drawn only where they face the camera.
  void _addWalls(int start, int deg, double px, double py, double pz, double lift, double facing) {
    // Thickness grows smoothly from nothing (facing the camera) to full at the limb.
    final w = ((0.86 - facing) / 0.22).clamp(0.0, 1.0).toDouble();
    if (w <= 0.01) return;
    final baseR = lift - (lift - 0.982) * w;
    final m = _m;
    // Shade like the tile top so walls on the dark side stay dark.
    final nx = m[0] * px + m[1] * py + m[2] * pz;
    final ny = m[3] * px + m[4] * py + m[5] * pz;
    final nz = m[6] * px + m[7] * py + m[8] * pz;
    var lam = nx * _lx + ny * _ly + nz * _lz;
    lam = lam < 0 ? 0 : lam;
    final k = 0.5 + 0.6 * lam;
    final top = packRgb(0.36 * k * _tr, 0.44 * k * _tg, 0.52 * k * _tb) | 0xFF000000;
    const bottom = 0xFF0A0F17;
    // Base of the wall, projected once per corner.
    for (var j = 0; j < deg; j++) {
      final ii = (start + j) * 3;
      _wallX[j] = 0;
      _wallY[j] = 0;
      final bx = _inset[ii] * baseR, by = _inset[ii + 1] * baseR, bz = _inset[ii + 2] * baseR;
      final x = m[0] * bx + m[1] * by + m[2] * bz;
      final y = m[3] * bx + m[4] * by + m[5] * bz;
      final z = m[6] * bx + m[7] * by + m[8] * bz;
      final depth = _d - z;
      _wallX[j] = _cx + _f * x / depth;
      _wallY[j] = _cy - _f * y / depth;
    }
    for (var j = 0; j < deg; j++) {
      final j2 = j + 1 == deg ? 0 : j + 1;
      final ax = _screen[(start + j) * 2], ay = _screen[(start + j) * 2 + 1];
      final bx = _screen[(start + j2) * 2], by = _screen[(start + j2) * 2 + 1];
      final a2x = _wallX[j], a2y = _wallY[j];
      final cross = (bx - ax) * (a2y - ay) - (by - ay) * (a2x - ax);
      if (cross > 0) continue; // faces away from the camera
      _wall.addQuad(ax, ay, bx, by, _wallX[j2], _wallY[j2], a2x, a2y, top, bottom);
    }
  }

  /// Soft glints on the tile edges that face the sun, and a darker line on the
  /// edges that face away: a cheap sense of raised plates.
  void _addEdgeGlints(int start, int deg, double ccx, double ccy, double facing) {
    var fade = (facing - 0.12) / 0.33;
    fade = fade < 0 ? 0 : (fade > 1 ? 1 : fade);
    if (fade <= 0) return;
    final ll = math.sqrt(_lx * _lx + _ly * _ly);
    final lsx = ll < 1e-6 ? 0.0 : _lx / ll;
    final lsy = ll < 1e-6 ? 0.0 : -_ly / ll;
    for (var j = 0; j < deg; j++) {
      final j2 = j + 1 == deg ? 0 : j + 1;
      final ax = _screen[(start + j) * 2], ay = _screen[(start + j) * 2 + 1];
      final bx = _screen[(start + j2) * 2], by = _screen[(start + j2) * 2 + 1];
      var ox = (ax + bx) / 2 - ccx, oy = (ay + by) / 2 - ccy;
      final ol = math.sqrt(ox * ox + oy * oy);
      if (ol < 0.5) continue;
      ox /= ol;
      oy /= ol;
      final d = ox * lsx + oy * lsy;
      if (d > 0.15) {
        _hi.addEdge(ax, ay, bx, by, 1.1, _argb(0.40 * d * d * fade, 0.85, 0.95, 1.0));
      } else if (d < -0.15) {
        _hi.addEdge(ax, ay, bx, by, 1.1, _argb(0.50 * d * d * fade, 0.0, 0.0, 0.0));
      }
    }
  }

  /// Which plate of the atlas shows a cell in logical state [st].
  static int _plateIndex(int st, int count, bool wrongFlag) {
    switch (st) {
      case CellCode.revealed:
        if (count <= 0) return TileAtlas.blank;
        return TileAtlas.number1 + (count > 8 ? 7 : count - 1);
      case CellCode.flagged:
        return wrongFlag ? TileAtlas.flagWrong : TileAtlas.flag;
      case CellCode.mineRevealed:
        return TileAtlas.mine;
      case CellCode.exploded:
        return TileAtlas.exploded;
      default:
        return TileAtlas.hidden;
    }
  }

  static int _argb(double a, double r, double g, double b) {
    int ch(double v) => (v < 0 ? 0 : (v > 1 ? 1 : v) * 255).toInt();
    return (ch(a) << 24) | (ch(r) << 16) | (ch(g) << 8) | ch(b);
  }

  // ---------------------------------------------------------------------------
  // Glyphs
  // ---------------------------------------------------------------------------

  void _paintGlyphs(Canvas canvas, GlobeRenderOptions o) {
    final shown = o.shown;
    final glyphs = o.glyphs;
    final counts = o.counts;
    if (shown == null || glyphs == null || counts == null) return;
    final atlas = glyphs.atlas;
    var n = 0;

    for (var c = 0; c < grid.cellCount; c++) {
      if (_visible[c] == 0) continue;
      final r = _cenR[c];
      if (r < 5) continue;
      final fc = _facing[c];
      var g = (fc - 0.26) / 0.40;
      g = g < 0 ? 0 : (g > 1 ? 1 : g);
      if (g <= 0.02) continue;
      final gs = g * g * (3 - 2 * g) * (0.55 + 0.45 * fc);
      final st = shown[c];
      int sprite;
      if (st == CellCode.revealed) {
        final k = counts[c];
        if (k == 0 || k > 8) continue;
        sprite = Sprite.digit1 + k - 1;
      } else if (st == CellCode.flagged) {
        sprite = (o.incorrect != null && o.incorrect![c] == 1) ? Sprite.flagWrong : Sprite.flag;
      } else if (st == CellCode.mineRevealed) {
        if (_texLast) continue; // the plate already shows the mine
        sprite = Sprite.mine;
      } else if (st == CellCode.exploded) {
        if (_texLast) continue;
        sprite = Sprite.mineExploded;
      } else {
        continue;
      }

      if (atlas == null) {
        glyphs.drawFallback(canvas, sprite, _cenX[c], _cenY[c], r);
        continue;
      }
      final s = r * gs * Sprite.factor / Sprite.natural;
      final half = GlyphCache.cell / 2;
      final i4 = n * 4;
      _atT[i4] = s; // scale * cos
      _atT[i4 + 1] = 0; // scale * sin
      _atT[i4 + 2] = _cenX[c] - s * half;
      _atT[i4 + 3] = _cenY[c] - s * half;
      GlyphCache.rectOf(sprite, _atR, i4);
      n++;
    }
    if (atlas != null && n > 0) {
      canvas.drawRawAtlas(
        atlas,
        Float32List.sublistView(_atT, 0, n * 4),
        Float32List.sublistView(_atR, 0, n * 4),
        null,
        null,
        null,
        _atlasPaint,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Highlights (selection / hover / markers)
  // ---------------------------------------------------------------------------

  void _paintHighlights(Canvas canvas, GlobeRenderOptions o) {
    if (o.selected >= 0) {
      final nbPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = HexfallTheme.amber.withAlpha(200);
      for (var k = grid.cellOffsets[o.selected]; k < grid.cellOffsets[o.selected + 1]; k++) {
        final path = _cellPath(grid.neighbourIndices[k]);
        if (path != null) canvas.drawPath(path, nbPaint);
      }
    }
    if (o.hovered >= 0 && o.hovered != o.selected) {
      final path = _cellPath(o.hovered);
      if (path != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = HexfallTheme.cyan.withAlpha(235),
        );
      }
    }
    if (o.marked.isNotEmpty) {
      final mp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = const Color(0xFFFF6A33);
      for (final c in o.marked) {
        final path = _cellPath(c);
        if (path != null) canvas.drawPath(path, mp);
      }
    }
    if (o.selected >= 0) {
      final path = _cellPath(o.selected);
      if (path != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.0
            ..color = HexfallTheme.cyan.withAlpha(70)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFEFFCFF),
        );
      }
    }
  }

  /// Screen position of a cell centre, or null if it faces away.
  Offset? cellScreenPosition(int c) => (c >= 0 && c < grid.cellCount && _visible[c] == 1)
      ? Offset(_cenX[c], _cenY[c])
      : null;

  double cellScreenRadius(int c) => _cenR[c];

  Path? _cellPath(int c) {
    if (c < 0 || c >= grid.cellCount || _visible[c] == 0) return null;
    final s = grid.cellOffsets[c];
    final e = grid.cellOffsets[c + 1];
    final path = Path()..moveTo(_screen[s * 2], _screen[s * 2 + 1]);
    for (var k = s + 1; k < e; k++) {
      path.lineTo(_screen[k * 2], _screen[k * 2 + 1]);
    }
    path.close();
    return path;
  }

  /// Rotates, projects and shades one vertex into the output buffers.
  void _vertex(int vi, double px, double py, double pz, double s, double r, double g, double b) {
    final m = _m;
    final x = (m[0] * px + m[1] * py + m[2] * pz) * s;
    final y = (m[3] * px + m[4] * py + m[5] * pz) * s;
    final z = (m[6] * px + m[7] * py + m[8] * pz) * s;
    final depth = _d - z;
    _pos[vi * 2] = _cx + _f * x / depth;
    _pos[vi * 2 + 1] = _cy - _f * y / depth;

    // Unit normal (the surface is a sphere, so normal == position / s).
    final inv = 1.0 / s;
    final nx = x * inv, ny = y * inv, nz = z * inv;
    var lam = nx * _lx + ny * _ly + nz * _lz;
    if (lam < 0) lam = 0;

    // Fresnel rim: brighter where the surface turns away from the viewer.
    final tl = math.sqrt(x * x + y * y + depth * depth);
    var ndv = (-nx * x - ny * y + nz * depth) / tl;
    if (ndv < 0) ndv = 0;
    if (ndv > 1) ndv = 1;
    final q = 1 - ndv;
    final fres = q * q * q * HexfallTheme.rimStrength;

    if (_tex) {
      // Textured plates: modulate colour = lighting, additive colour = effects.
      var k = _lf + (1.02 - _lf) * lam;
      if (k > 1) k = 1;
      k *= _vb;
      _col[vi] = packRgb(k * _tr, k * _tg, k * _tb);
      const rimc = HexfallTheme.rimColor;
      var ar = rimc[0] * fres * 0.8 + _hr, ag = rimc[1] * fres * 0.8 + _hg, ab = rimc[2] * fres * 0.8 + _hb;
      if (_scan) {
        final dd = y - _scanY;
        if (dd < 0.4 && dd > -0.4) {
          final band = math.exp(-dd * dd / _scanWidth) * 0.16;
          ar += 0.10 * band;
          ag += 0.85 * band;
          ab += 1.00 * band;
        }
      }
      if (_flash > 0) {
        ar += _fR * _flash * 0.8;
        ag += _fG * _flash * 0.8;
        ab += _fB * _flash * 0.8;
      }
      if (_pu > 0) {
        ar += 0.30 * _pu;
        ag += 0.70 * _pu;
        ab += 0.70 * _pu;
      }
      _colAdd[vi] = packRgb(ar, ag, ab);
      return;
    }

    final shade = HexfallTheme.ambient + HexfallTheme.diffuse * lam;
    const rim = HexfallTheme.rimColor;
    var rr = r * shade + rim[0] * fres;
    var gg = g * shade + rim[1] * fres;
    var bb = b * shade + rim[2] * fres;

    if (_scan) {
      final dd = y - _scanY;
      if (dd < 0.4 && dd > -0.4) {
        final band = math.exp(-dd * dd / _scanWidth) * 0.22;
        rr += 0.10 * band;
        gg += 0.85 * band;
        bb += 1.00 * band;
      }
    }
    if (_flash > 0) {
      rr += _fR * _flash;
      gg += _fG * _flash;
      bb += _fB * _flash;
    }
    if (_pu > 0) {
      rr += 0.45 * _pu;
      gg += 1.00 * _pu;
      bb += 1.00 * _pu;
    }
    _col[vi] = packRgb(rr * _vb, gg * _vb, bb * _vb);
  }
}
