import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/geometry/geodesic_grid.dart';
import 'package:hexfall/core/geometry/vec3.dart';
import 'package:hexfall/render/globe_camera.dart';

void main() {
  const size = Size(800, 600);

  Offset project(GlobeCamera cam, Vec3 p) {
    final proj = cam.projection(size);
    final m = cam.matrix;
    final x = m[0] * p.x + m[1] * p.y + m[2] * p.z;
    final y = m[3] * p.x + m[4] * p.y + m[5] * p.z;
    final z = m[6] * p.x + m[7] * p.y + m[8] * p.z;
    final depth = proj.distance - z;
    return Offset(proj.cx + proj.focal * x / depth, proj.cy - proj.focal * y / depth);
  }

  group('GlobeCamera', () {
    test('screen centre hits the point facing the camera', () {
      final cam = GlobeCamera();
      final hit = cam.screenToPlanet(const Offset(400, 300), size)!;
      expect(hit.x, closeTo(0, 1e-9));
      expect(hit.y, closeTo(0, 1e-9));
      expect(hit.z, closeTo(1, 1e-9));
    });

    test('rays that miss the planet return null', () {
      final cam = GlobeCamera();
      expect(cam.screenToPlanet(const Offset(2, 2), size), isNull);
    });

    test('silhouette radius matches the picking limb', () {
      final cam = GlobeCamera();
      final r = cam.projection(size).radiusPx;
      expect(cam.screenToPlanet(Offset(400 + r * 0.98, 300), size), isNotNull);
      expect(cam.screenToPlanet(Offset(400 + r * 1.02, 300), size), isNull);
    });

    test('project then pick round-trips for arbitrary orientations', () {
      final cam = GlobeCamera();
      cam.rotateView(0.7, -1.1, 0.4);
      cam.rotateView(-0.3, 0.9, 1.2);
      cam.zoomBy(1.3);
      final rnd = math.Random(5);
      var tested = 0;
      while (tested < 200) {
        final z = rnd.nextDouble() * 2 - 1;
        final a = rnd.nextDouble() * 2 * math.pi;
        final r = math.sqrt(1 - z * z);
        final p = Vec3(r * math.cos(a), r * math.sin(a), z);
        // Only points facing the camera can be picked.
        final m = cam.matrix;
        final viewZ = m[6] * p.x + m[7] * p.y + m[8] * p.z;
        if (viewZ < 1 / cam.distance + 0.05) continue;
        final screen = project(cam, p);
        final back = cam.screenToPlanet(screen, size)!;
        expect((back - p).length, lessThan(1e-9));
        tested++;
      }
    });

    test('rotation matrix stays orthonormal after many drags', () {
      final cam = GlobeCamera();
      for (var i = 0; i < 5000; i++) {
        cam.dragBy(math.sin(i * 0.1) * 7, math.cos(i * 0.07) * 5, size);
      }
      final m = cam.matrix;
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          var dot = 0.0;
          for (var k = 0; k < 3; k++) {
            dot += m[r * 3 + k] * m[c * 3 + k];
          }
          expect(dot, closeTo(r == c ? 1 : 0, 1e-9));
        }
      }
    });

    test('dragging right moves the surface right', () {
      final cam = GlobeCamera();
      final before = project(cam, const Vec3(0, 0, 1));
      cam.dragBy(40, 0, size);
      // The point that was at the centre should now be to the right.
      final after = project(cam, const Vec3(0, 0, 1));
      expect(after.dx, greaterThan(before.dx));
      expect(after.dy, closeTo(before.dy, 1e-6));
    });

    test('dragging down moves the surface down', () {
      final cam = GlobeCamera();
      final before = project(cam, const Vec3(0, 0, 1));
      cam.dragBy(0, 40, size);
      final after = project(cam, const Vec3(0, 0, 1));
      expect(after.dy, greaterThan(before.dy));
      expect(after.dx, closeTo(before.dx, 1e-6));
    });

    test('zoom is clamped to its limits', () {
      final cam = GlobeCamera();
      cam.zoomBy(100);
      expect(cam.distance, GlobeCamera.minDistance);
      cam.zoomBy(0.001);
      expect(cam.distance, GlobeCamera.maxDistance);
    });

    test('focusOn brings a cell to the centre of the view', () {
      final cam = GlobeCamera();
      cam.rotateView(1.0, 2.0, -0.5);
      const target = Vec3(0.3, -0.6, 0.7416198487095663);
      final p = target.normalized();
      cam.focusOn(p);
      for (var i = 0; i < 600; i++) {
        cam.tick(1 / 60);
      }
      expect(cam.isAnimating, isFalse);
      final screen = project(cam, p);
      expect(screen.dx, closeTo(400, 0.5));
      expect(screen.dy, closeTo(300, 0.5));
    });

    test('inertia decays to rest', () {
      final cam = GlobeCamera();
      cam.spinX = 3;
      cam.spinY = -2;
      for (var i = 0; i < 600; i++) {
        cam.tick(1 / 60);
      }
      expect(cam.hasInertia, isFalse);
    });

    test('picking through the camera finds the expected cell', () {
      final grid = GeodesicGrid.generate(8);
      final cam = GlobeCamera();
      cam.rotateView(0.4, 0.8, 0.0);
      // Choose a front-facing cell, project its centre, and pick it back.
      final m = cam.matrix;
      var checked = 0;
      for (final cell in grid.cells) {
        final p = cell.position;
        final viewZ = m[6] * p.x + m[7] * p.y + m[8] * p.z;
        if (viewZ < 0.5) continue;
        final screen = project(cam, p);
        final hit = cam.screenToPlanet(screen, size)!;
        expect(grid.cellAt(hit.x, hit.y, hit.z), cell.id);
        checked++;
      }
      expect(checked, greaterThan(50));
    });
  });
}
