import 'dart:math' as math;
import 'dart:typed_data';

import 'vec3.dart';

/// A single cell (tile) of the planet: a hexagon, or one of the 12 pentagons.
///
/// This is the friendly, object-style view of the grid used by game logic,
/// the UI and tests. The renderer reads the packed arrays on [GeodesicGrid]
/// directly for speed.
class HexCell {
  const HexCell({
    required this.id,
    required this.position,
    required this.boundary,
    required this.neighbours,
  });

  /// Unique, stable identifier (0 .. cellCount-1).
  final int id;

  /// Centre of the cell on the unit sphere.
  final Vec3 position;

  /// Outward surface normal. On a unit sphere this equals [position].
  Vec3 get normal => position;

  /// Boundary corners on the unit sphere, counter-clockwise seen from outside.
  final List<Vec3> boundary;

  /// Adjacent cell ids. `neighbours[k]` is the cell across the edge between
  /// `boundary[k]` and `boundary[(k + 1) % sides]`.
  final List<int> neighbours;

  int get sides => neighbours.length;
  bool get isPentagon => neighbours.length == 5;
  bool get isHexagon => neighbours.length == 6;

  @override
  String toString() => 'HexCell($id, ${isPentagon ? 'pentagon' : 'hexagon'})';
}

/// A closed geodesic sphere built as the dual of a subdivided icosahedron.
///
/// For subdivision frequency `n` there are `10 n^2 + 2` cells: exactly 12
/// pentagons (the original icosahedron corners) and hexagons everywhere else.
///
/// Construction:
///  1. Start from a regular icosahedron.
///  2. Subdivide every face into `n^2` triangles and push the new vertices onto
///     the unit sphere. Shared edge vertices are de-duplicated *topologically*
///     (by edge + step index), never by comparing floating point positions.
///  3. Each mesh vertex becomes a cell. Each mesh triangle becomes a corner
///     shared by exactly three cells. Cells and corners are therefore
///     perfectly consistent: no gaps, no duplicate points, no bent flat grid.
///
/// All data is stored in packed typed lists (CSR layout) so the renderer and
/// picking code can iterate without allocating.
class GeodesicGrid {
  GeodesicGrid._({
    required this.frequency,
    required this.centers,
    required this.dualVertices,
    required this.cellOffsets,
    required this.cellVertexIndices,
    required this.neighbourIndices,
  }) : cellCount = centers.length ~/ 3 {
    cells = List<HexCell>.generate(cellCount, _buildCell, growable: false);
  }

  static const int minFrequency = 1;
  static const int maxFrequency = 24;

  /// Expected number of cells for a frequency: 10 n^2 + 2.
  static int cellCountFor(int frequency) => 10 * frequency * frequency + 2;

  /// Subdivision frequency `n`.
  final int frequency;

  /// Number of cells (10 n^2 + 2).
  final int cellCount;

  /// Cell centres, xyz packed, unit length. Length = 3 * cellCount.
  final Float64List centers;

  /// Cell corner points, xyz packed, unit length. Corner `t` is shared by
  /// exactly three cells. Length = 3 * 20 n^2.
  final Float64List dualVertices;

  /// CSR offsets. Cell `c` owns entries `cellOffsets[c] .. cellOffsets[c+1]-1`
  /// in [cellVertexIndices] and [neighbourIndices]. Length = cellCount + 1.
  final Int32List cellOffsets;

  /// For each cell, indices into [dualVertices] in counter-clockwise order.
  final Int32List cellVertexIndices;

  /// For each cell, adjacent cell ids. Entry `k` lies across the edge between
  /// corner `k` and corner `k + 1` of the same cell.
  final Int32List neighbourIndices;

  /// Object view of every cell (index == cell id).
  late final List<HexCell> cells;

  int get dualVertexCount => dualVertices.length ~/ 3;

  /// Number of sides (5 or 6) of cell [id].
  int sidesOf(int id) => cellOffsets[id + 1] - cellOffsets[id];

  /// Number of pentagonal cells (should always be 12).
  int get pentagonCount {
    var count = 0;
    for (var c = 0; c < cellCount; c++) {
      if (sidesOf(c) == 5) count++;
    }
    return count;
  }

  Vec3 centerOf(int id) =>
      Vec3(centers[id * 3], centers[id * 3 + 1], centers[id * 3 + 2]);

  HexCell _buildCell(int id) {
    final start = cellOffsets[id];
    final end = cellOffsets[id + 1];
    final boundary = <Vec3>[];
    final neighbours = <int>[];
    for (var k = start; k < end; k++) {
      final d = cellVertexIndices[k] * 3;
      boundary.add(Vec3(dualVertices[d], dualVertices[d + 1], dualVertices[d + 2]));
      neighbours.add(neighbourIndices[k]);
    }
    return HexCell(
      id: id,
      position: centerOf(id),
      boundary: List<Vec3>.unmodifiable(boundary),
      neighbours: List<int>.unmodifiable(neighbours),
    );
  }

  // ---------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------

  /// Exact test: is the unit-sphere point (x, y, z) inside cell [cell]?
  /// Cell edges are great-circle arcs, so the test is a sign check against
  /// each edge plane.
  bool containsPoint(int cell, double x, double y, double z) {
    final start = cellOffsets[cell];
    final end = cellOffsets[cell + 1];
    for (var k = start; k < end; k++) {
      final a = cellVertexIndices[k] * 3;
      final b = cellVertexIndices[k + 1 < end ? k + 1 : start] * 3;
      final ax = dualVertices[a], ay = dualVertices[a + 1], az = dualVertices[a + 2];
      final bx = dualVertices[b], by = dualVertices[b + 1], bz = dualVertices[b + 2];
      final cx = ay * bz - az * by;
      final cy = az * bx - ax * bz;
      final cz = ax * by - ay * bx;
      if (cx * x + cy * y + cz * z < -1e-12) return false;
    }
    return true;
  }

  /// Returns the id of the cell containing the direction (x, y, z) (does not
  /// need to be normalised). Always returns a valid id.
  int cellAt(double x, double y, double z) {
    final len = math.sqrt(x * x + y * y + z * z);
    if (len == 0) return 0;
    final px = x / len, py = y / len, pz = z / len;

    var best = 0;
    var bestDot = -2.0;
    for (var c = 0; c < cellCount; c++) {
      final i = c * 3;
      final d = centers[i] * px + centers[i + 1] * py + centers[i + 2] * pz;
      if (d > bestDot) {
        bestDot = d;
        best = c;
      }
    }
    if (containsPoint(best, px, py, pz)) return best;
    for (var k = cellOffsets[best]; k < cellOffsets[best + 1]; k++) {
      final nb = neighbourIndices[k];
      if (containsPoint(nb, px, py, pz)) return nb;
    }
    return best; // Numerical edge case: point lies on a boundary.
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  /// Builds a grid of the given subdivision [frequency] (1 .. 24).
  factory GeodesicGrid.generate(int frequency) {
    if (frequency < minFrequency || frequency > maxFrequency) {
      throw ArgumentError.value(
        frequency,
        'frequency',
        'must be between $minFrequency and $maxFrequency',
      );
    }
    final n = frequency;

    // --- 1. Icosahedron ------------------------------------------------------
    final t = (1.0 + math.sqrt(5.0)) / 2.0;
    final base = <Vec3>[];
    for (final v in <List<double>>[
      [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
      [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
      [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
    ]) {
      base.add(Vec3(v[0], v[1], v[2]).normalized());
    }
    // 20 faces, all wound counter-clockwise seen from outside.
    const faces = <List<int>>[
      [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
      [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
      [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
      [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
    ];

    // --- 2. Subdivide --------------------------------------------------------
    final pos = <double>[];
    final tris = <int>[]; // 3 vertex indices per triangle

    int addVertex(Vec3 p) {
      pos
        ..add(p.x)
        ..add(p.y)
        ..add(p.z);
      return pos.length ~/ 3 - 1;
    }

    for (final v in base) {
      addVertex(v); // vertices 0..11 are the icosahedron corners
    }

    final edgeCache = <int, int>{};
    int edgeVertex(int p, int q, int steps) {
      // Canonical direction so both faces sharing an edge agree exactly.
      var a = p, b = q, s = steps;
      if (a > b) {
        a = q;
        b = p;
        s = n - steps;
      }
      final key = (a * 12 + b) * (n + 1) + s;
      final cached = edgeCache[key];
      if (cached != null) return cached;
      final v = (base[a] * (n - s).toDouble() + base[b] * s.toDouble()).normalized();
      final idx = addVertex(v);
      edgeCache[key] = idx;
      return idx;
    }

    for (final f in faces) {
      final a = base[f[0]], b = base[f[1]], c = base[f[2]];
      // g[i][j]: i steps towards B, j steps towards C, k = n - i - j towards A.
      final g = List<List<int>>.generate(n + 1, (i) => List<int>.filled(n + 1 - i, -1));
      for (var i = 0; i <= n; i++) {
        for (var j = 0; j <= n - i; j++) {
          final k = n - i - j;
          int idx;
          if (k == n) {
            idx = f[0];
          } else if (i == n) {
            idx = f[1];
          } else if (j == n) {
            idx = f[2];
          } else if (k == 0) {
            idx = edgeVertex(f[1], f[2], j); // edge B-C
          } else if (i == 0) {
            idx = edgeVertex(f[0], f[2], j); // edge A-C
          } else if (j == 0) {
            idx = edgeVertex(f[0], f[1], i); // edge A-B
          } else {
            final p = (a * k.toDouble() + b * i.toDouble() + c * j.toDouble()).normalized();
            idx = addVertex(p);
          }
          g[i][j] = idx;
        }
      }
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n - i; j++) {
          tris
            ..add(g[i][j])
            ..add(g[i + 1][j])
            ..add(g[i][j + 1]);
          if (i + j < n - 1) {
            tris
              ..add(g[i + 1][j])
              ..add(g[i + 1][j + 1])
              ..add(g[i][j + 1]);
          }
        }
      }
    }

    final vertexCount = pos.length ~/ 3;
    final triCount = tris.length ~/ 3;

    // --- 3. Dual mesh --------------------------------------------------------
    // Triangle centroids are the cell corners.
    final dual = Float64List(triCount * 3);
    for (var ti = 0; ti < triCount; ti++) {
      var x = 0.0, y = 0.0, z = 0.0;
      for (var k = 0; k < 3; k++) {
        final v = tris[ti * 3 + k] * 3;
        x += pos[v];
        y += pos[v + 1];
        z += pos[v + 2];
      }
      final l = math.sqrt(x * x + y * y + z * z);
      dual[ti * 3] = x / l;
      dual[ti * 3 + 1] = y / l;
      dual[ti * 3 + 2] = z / l;
    }

    final incident = List<List<int>>.generate(vertexCount, (_) => <int>[]);
    for (var ti = 0; ti < triCount; ti++) {
      for (var k = 0; k < 3; k++) {
        incident[tris[ti * 3 + k]].add(ti);
      }
    }

    final centers = Float64List(vertexCount * 3);
    final offsets = Int32List(vertexCount + 1);
    final cornerList = <int>[];
    final neighbourList = <int>[];

    for (var v = 0; v < vertexCount; v++) {
      final cx = pos[v * 3], cy = pos[v * 3 + 1], cz = pos[v * 3 + 2];
      centers[v * 3] = cx;
      centers[v * 3 + 1] = cy;
      centers[v * 3 + 2] = cz;

      // Tangent basis at the cell centre; t2 = c x t1 gives counter-clockwise
      // angles when viewed from outside the sphere.
      final c = Vec3(cx, cy, cz);
      final helper = cx.abs() < 0.9 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
      final t1 = c.cross(helper).normalized();
      final t2 = c.cross(t1);

      final list = incident[v];
      final angle = <int, double>{};
      for (final ti in list) {
        final d = Vec3(dual[ti * 3], dual[ti * 3 + 1], dual[ti * 3 + 2]);
        angle[ti] = math.atan2(d.dot(t2), d.dot(t1));
      }
      list.sort((a, b) => angle[a]!.compareTo(angle[b]!));

      final deg = list.length;
      for (var k = 0; k < deg; k++) {
        final ta = list[k];
        final tb = list[(k + 1) % deg];
        cornerList.add(ta);
        // Consecutive triangles around v share the edge (v, w): w is the
        // neighbouring cell across this cell edge.
        var w = -1;
        for (var i = 0; i < 3; i++) {
          final cand = tris[ta * 3 + i];
          if (cand == v) continue;
          for (var j = 0; j < 3; j++) {
            if (tris[tb * 3 + j] == cand) w = cand;
          }
        }
        neighbourList.add(w);
      }
      offsets[v + 1] = cornerList.length;
    }

    return GeodesicGrid._(
      frequency: n,
      centers: centers,
      dualVertices: dual,
      cellOffsets: offsets,
      cellVertexIndices: Int32List.fromList(cornerList),
      neighbourIndices: Int32List.fromList(neighbourList),
    );
  }
}
