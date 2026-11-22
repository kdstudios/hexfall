import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/geometry/geodesic_grid.dart';
import 'package:hexfall/core/geometry/grid_validator.dart';

void main() {
  // Frequencies: 1 (dodecahedron), small edge cases, and the four presets.
  const frequencies = [1, 2, 3, 4, 8, 10, 16];

  group('GeodesicGrid structure', () {
    for (final n in frequencies) {
      test('n=$n: cell count is 10n²+2', () {
        final g = GeodesicGrid.generate(n);
        expect(g.cellCount, 10 * n * n + 2);
        expect(g.cells.length, g.cellCount);
      });

      test('n=$n: exactly 12 pentagons, every other cell a hexagon', () {
        final g = GeodesicGrid.generate(n);
        final pentagons = g.cells.where((c) => c.isPentagon).length;
        final hexagons = g.cells.where((c) => c.isHexagon).length;
        expect(pentagons, 12);
        expect(hexagons, g.cellCount - 12);
        expect(g.pentagonCount, 12);
      });

      test('n=$n: neighbours unique, valid and reciprocal', () {
        final g = GeodesicGrid.generate(n);
        for (final cell in g.cells) {
          expect(cell.neighbours.length, cell.boundary.length);
          expect(cell.neighbours.toSet().length, cell.neighbours.length,
              reason: 'duplicate neighbour on ${cell.id}');
          expect(cell.neighbours.contains(cell.id), isFalse);
          for (final nb in cell.neighbours) {
            expect(nb, inInclusiveRange(0, g.cellCount - 1));
            expect(g.cells[nb].neighbours.contains(cell.id), isTrue,
                reason: '${cell.id} -> $nb is not reciprocal');
          }
        }
      });

      test('n=$n: surface is a single connected component', () {
        final g = GeodesicGrid.generate(n);
        final seen = <int>{0};
        final queue = <int>[0];
        while (queue.isNotEmpty) {
          final c = queue.removeLast();
          for (final nb in g.cells[c].neighbours) {
            if (seen.add(nb)) queue.add(nb);
          }
        }
        expect(seen.length, g.cellCount);
      });

      test('n=$n: all cell data lies on the unit sphere', () {
        final g = GeodesicGrid.generate(n);
        for (final cell in g.cells) {
          expect(cell.position.length, closeTo(1, 1e-12));
          for (final v in cell.boundary) {
            expect(v.length, closeTo(1, 1e-12));
          }
        }
      });

      test('n=$n: full validator passes', () {
        final report = GridValidator.validate(GeodesicGrid.generate(n));
        for (final check in report.checks) {
          expect(check.passed, isTrue, reason: '${check.name}: ${check.detail}');
        }
      });
    }

    test('preset cell counts match the design document', () {
      expect(GeodesicGrid.generate(4).cellCount, 162);
      expect(GeodesicGrid.generate(8).cellCount, 642);
      expect(GeodesicGrid.generate(10).cellCount, 1002);
      expect(GeodesicGrid.generate(16).cellCount, 2562);
    });

    test('n=1 is a dodecahedron (12 pentagons, no hexagons)', () {
      final g = GeodesicGrid.generate(1);
      expect(g.cells.every((c) => c.isPentagon), isTrue);
    });

    test('generation is deterministic', () {
      final a = GeodesicGrid.generate(6);
      final b = GeodesicGrid.generate(6);
      expect(a.centers, b.centers);
      expect(a.neighbourIndices, b.neighbourIndices);
    });

    test('rejects unsupported frequencies', () {
      expect(() => GeodesicGrid.generate(0), throwsArgumentError);
      expect(() => GeodesicGrid.generate(GeodesicGrid.maxFrequency + 1), throwsArgumentError);
    });

    test('maximum supported frequency stays within 16-bit mesh indices', () {
      // The renderer uses Uint16 indices: cells + corners vertices per frame.
      final cells = GeodesicGrid.cellCountFor(GeodesicGrid.maxFrequency);
      final corners = 6 * cells - 12;
      expect(cells + corners, lessThan(65536));
    });
  });

  group('GeodesicGrid picking', () {
    for (final n in [4, 8, 16]) {
      test('n=$n: every cell centre picks itself', () {
        final g = GeodesicGrid.generate(n);
        for (final cell in g.cells) {
          final p = cell.position;
          expect(g.cellAt(p.x, p.y, p.z), cell.id);
        }
      });

      test('n=$n: random points are contained in exactly the picked cell', () {
        final g = GeodesicGrid.generate(n);
        final rnd = math.Random(42);
        for (var i = 0; i < 3000; i++) {
          // Uniform random direction.
          final z = rnd.nextDouble() * 2 - 1;
          final a = rnd.nextDouble() * 2 * math.pi;
          final r = math.sqrt(1 - z * z);
          final x = r * math.cos(a), y = r * math.sin(a);

          final picked = g.cellAt(x, y, z);
          expect(g.containsPoint(picked, x, y, z), isTrue);

          // Brute force: no other cell may also strictly contain it.
          var count = 0;
          for (var c = 0; c < g.cellCount; c++) {
            if (g.containsPoint(c, x, y, z)) count++;
          }
          // 1 normally; boundary points (measure zero) may touch 2-3.
          expect(count, inInclusiveRange(1, 3));
        }
      });
    }
  });
}
