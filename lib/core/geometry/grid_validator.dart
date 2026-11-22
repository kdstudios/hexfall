import 'dart:math' as math;

import 'geodesic_grid.dart';

class ValidationCheck {
  const ValidationCheck(this.name, this.passed, this.detail);

  final String name;
  final bool passed;
  final String detail;
}

class GridValidationReport {
  const GridValidationReport(this.checks);

  final List<ValidationCheck> checks;

  bool get passed => checks.every((c) => c.passed);
  int get failureCount => checks.where((c) => !c.passed).length;
}

/// Mathematical self-check of a [GeodesicGrid]. Used by the automated tests and
/// shown live in the sandbox UI, so a broken grid can never go unnoticed.
class GridValidator {
  const GridValidator._();

  static GridValidationReport validate(GeodesicGrid g) {
    final checks = <ValidationCheck>[];
    final n = g.frequency;
    final cells = g.cellCount;

    // 1. Cell count --------------------------------------------------------
    final expected = GeodesicGrid.cellCountFor(n);
    checks.add(ValidationCheck(
      'Cell count = 10n²+2',
      cells == expected,
      '$cells cells (expected $expected)',
    ));

    // 2/3. Pentagons and hexagons ---------------------------------------------
    var pent = 0, hex = 0, other = 0;
    for (var c = 0; c < cells; c++) {
      switch (g.sidesOf(c)) {
        case 5:
          pent++;
        case 6:
          hex++;
        default:
          other++;
      }
    }
    checks.add(ValidationCheck(
      'Exactly 12 pentagons',
      pent == 12,
      '$pent pentagons',
    ));
    checks.add(ValidationCheck(
      'Every other cell is a hexagon',
      other == 0 && hex == cells - 12,
      '$hex hexagons, $other irregular',
    ));

    // 4. Polygon corners match neighbours ------------------------------------
    var shapeOk = true;
    for (var c = 0; c < cells; c++) {
      final s = g.cellOffsets[c];
      final e = g.cellOffsets[c + 1];
      if (e - s != g.cells[c].boundary.length ||
          g.cells[c].boundary.length != g.cells[c].neighbours.length) {
        shapeOk = false;
      }
    }
    checks.add(ValidationCheck(
      'Corners == neighbours per cell',
      shapeOk,
      shapeOk ? 'all cells consistent' : 'mismatch found',
    ));

    // 5. Neighbour lists are valid (range, no self, no duplicates) -----------
    var validNbrs = true;
    for (var c = 0; c < cells && validNbrs; c++) {
      final seen = <int>{};
      for (var k = g.cellOffsets[c]; k < g.cellOffsets[c + 1]; k++) {
        final nb = g.neighbourIndices[k];
        if (nb < 0 || nb >= cells || nb == c || !seen.add(nb)) {
          validNbrs = false;
          break;
        }
      }
    }
    checks.add(ValidationCheck(
      'No missing, self or duplicate neighbours',
      validNbrs,
      validNbrs ? 'all lists valid' : 'invalid neighbour list',
    ));

    // 6. Reciprocity ---------------------------------------------------------
    var reciprocal = validNbrs;
    for (var c = 0; c < cells && reciprocal; c++) {
      for (var k = g.cellOffsets[c]; k < g.cellOffsets[c + 1]; k++) {
        final nb = g.neighbourIndices[k];
        var found = false;
        for (var j = g.cellOffsets[nb]; j < g.cellOffsets[nb + 1]; j++) {
          if (g.neighbourIndices[j] == c) {
            found = true;
            break;
          }
        }
        if (!found) {
          reciprocal = false;
          break;
        }
      }
    }
    checks.add(ValidationCheck(
      'Neighbour relationships are reciprocal',
      reciprocal,
      reciprocal ? 'A→B implies B→A' : 'one-way link found',
    ));

    // 7. Neighbour k shares exactly corners k and k+1 --------------------------
    var edgesOk = validNbrs;
    for (var c = 0; c < cells && edgesOk; c++) {
      final s = g.cellOffsets[c];
      final e = g.cellOffsets[c + 1];
      for (var k = s; k < e; k++) {
        final a = g.cellVertexIndices[k];
        final b = g.cellVertexIndices[k + 1 < e ? k + 1 : s];
        final nb = g.neighbourIndices[k];
        final ns = g.cellOffsets[nb];
        final ne = g.cellOffsets[nb + 1];
        var hasA = false, hasB = false;
        var shared = 0;
        for (var j = ns; j < ne; j++) {
          final v = g.cellVertexIndices[j];
          if (v == a) hasA = true;
          if (v == b) hasB = true;
          for (var m = s; m < e; m++) {
            if (g.cellVertexIndices[m] == v) shared++;
          }
        }
        if (!(hasA && hasB && shared == 2)) {
          edgesOk = false;
          break;
        }
      }
    }
    checks.add(ValidationCheck(
      'Adjacent cells share exactly one edge',
      edgesOk,
      edgesOk ? 'no gaps or overlaps' : 'edge mismatch',
    ));

    // 8. Every corner belongs to exactly three cells -------------------------
    final usage = List<int>.filled(g.dualVertexCount, 0);
    for (var k = 0; k < g.cellVertexIndices.length; k++) {
      usage[g.cellVertexIndices[k]]++;
    }
    final closed = usage.every((u) => u == 3);
    checks.add(ValidationCheck(
      'Surface closed (each corner in 3 cells)',
      closed,
      closed ? '${g.dualVertexCount} corners' : 'open corner found',
    ));

    // 9. Euler characteristic -------------------------------------------------
    final edges = g.cellVertexIndices.length ~/ 2;
    final euler = cells - edges + g.dualVertexCount;
    checks.add(ValidationCheck(
      'Euler characteristic V−E+F = 2',
      euler == 2 && edges == 30 * n * n,
      'V=${g.dualVertexCount} E=$edges F=$cells → $euler',
    ));

    // 10. Connectivity --------------------------------------------------------
    final seen = List<bool>.filled(cells, false);
    final stack = <int>[0];
    seen[0] = true;
    var reached = 1;
    if (validNbrs) {
      while (stack.isNotEmpty) {
        final c = stack.removeLast();
        for (var k = g.cellOffsets[c]; k < g.cellOffsets[c + 1]; k++) {
          final nb = g.neighbourIndices[k];
          if (!seen[nb]) {
            seen[nb] = true;
            reached++;
            stack.add(nb);
          }
        }
      }
    }
    checks.add(ValidationCheck(
      'Single connected spherical surface',
      reached == cells,
      'reached $reached of $cells',
    ));

    // 11. Convex, counter-clockwise polygons containing their centre ---------
    var convex = true;
    for (var c = 0; c < cells && convex; c++) {
      final s = g.cellOffsets[c];
      final e = g.cellOffsets[c + 1];
      for (var k = s; k < e; k++) {
        final a = g.cellVertexIndices[k] * 3;
        final b = g.cellVertexIndices[k + 1 < e ? k + 1 : s] * 3;
        final ax = g.dualVertices[a], ay = g.dualVertices[a + 1], az = g.dualVertices[a + 2];
        final bx = g.dualVertices[b], by = g.dualVertices[b + 1], bz = g.dualVertices[b + 2];
        final cx = ay * bz - az * by;
        final cy = az * bx - ax * bz;
        final cz = ax * by - ay * bx;
        final i = c * 3;
        if (cx * g.centers[i] + cy * g.centers[i + 1] + cz * g.centers[i + 2] <= 0) {
          convex = false;
          break;
        }
      }
    }
    checks.add(ValidationCheck(
      'Cells convex, ordered, contain centre',
      convex,
      convex ? 'all cells well-formed' : 'malformed cell',
    ));

    // 12. Total spherical area = 4π --------------------------------------------
    var area = 0.0;
    for (var c = 0; c < cells; c++) {
      final s = g.cellOffsets[c];
      final e = g.cellOffsets[c + 1];
      final i = c * 3;
      final px = g.centers[i], py = g.centers[i + 1], pz = g.centers[i + 2];
      for (var k = s; k < e; k++) {
        final a = g.cellVertexIndices[k] * 3;
        final b = g.cellVertexIndices[k + 1 < e ? k + 1 : s] * 3;
        final ax = g.dualVertices[a], ay = g.dualVertices[a + 1], az = g.dualVertices[a + 2];
        final bx = g.dualVertices[b], by = g.dualVertices[b + 1], bz = g.dualVertices[b + 2];
        // Spherical triangle (p, a, b), Van Oosterom–Strakhov formula.
        final tx = ay * bz - az * by;
        final ty = az * bx - ax * bz;
        final tz = ax * by - ay * bx;
        final triple = (px * tx + py * ty + pz * tz).abs();
        final denom = 1 + px * ax + py * ay + pz * az + ax * bx + ay * by + az * bz + bx * px + by * py + bz * pz;
        area += 2 * math.atan2(triple, denom);
      }
    }
    final areaError = (area - 4 * math.pi).abs();
    checks.add(ValidationCheck(
      'Cell areas sum to 4π',
      areaError < 1e-8,
      'error ${areaError.toStringAsExponential(2)}',
    ));

    return GridValidationReport(checks);
  }
}
