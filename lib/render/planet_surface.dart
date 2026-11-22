import 'dart:math' as math;

import '../core/planet/planet_environment.dart';

/// Simple deterministic procedural surface used to give the Milestone 1 globe a
/// believable "alien ocean world" look. Milestone 5 replaces the palette with
/// per-environment presets; the noise stays.
///
/// IMPORTANT: the hash below only uses integer operations that are exact in
/// JavaScript (every product stays below 2^53 and every step is masked to 32
/// bits), so the same seed produces the same planet on Android, iOS and Web.
/// That matters later for the Daily Planet.
class PlanetSurface {
  PlanetSurface(this.seed, this.style);

  final int seed;
  final PlanetStyle style;

  static int _mix(int h) {
    h &= 0xFFFFFFFF;
    h ^= h ~/ 32768;
    h &= 0xFFFFFFFF;
    h = (h * 0x2C1B3) & 0xFFFFFFFF;
    h ^= h ~/ 4096;
    h &= 0xFFFFFFFF;
    h = (h * 0x1B873) & 0xFFFFFFFF;
    h ^= h ~/ 32768;
    return h & 0xFFFFFFFF;
  }

  double _lattice(int x, int y, int z) {
    var h = (seed & 0xFFFFFFFF) ^ 0x9E3779B1;
    h = _mix(h ^ ((x * 73856093) & 0xFFFFFFFF));
    h = _mix(h ^ ((y * 19349663) & 0xFFFFFFFF));
    h = _mix(h ^ ((z * 83492791) & 0xFFFFFFFF));
    return h / 4294967295.0;
  }

  static double _smooth(double t) => t * t * (3 - 2 * t);

  double _noise(double x, double y, double z) {
    final x0 = x.floor(), y0 = y.floor(), z0 = z.floor();
    final fx = _smooth(x - x0), fy = _smooth(y - y0), fz = _smooth(z - z0);
    double l(int dx, int dy, int dz) => _lattice(x0 + dx, y0 + dy, z0 + dz);
    final c00 = l(0, 0, 0) + (l(1, 0, 0) - l(0, 0, 0)) * fx;
    final c10 = l(0, 1, 0) + (l(1, 1, 0) - l(0, 1, 0)) * fx;
    final c01 = l(0, 0, 1) + (l(1, 0, 1) - l(0, 0, 1)) * fx;
    final c11 = l(0, 1, 1) + (l(1, 1, 1) - l(0, 1, 1)) * fx;
    final c0 = c00 + (c10 - c00) * fy;
    final c1 = c01 + (c11 - c01) * fy;
    return c0 + (c1 - c0) * fz;
  }

  /// Fractal height in 0..1 for a point on the unit sphere.
  double height(double x, double y, double z) {
    var amp = 0.5, freq = style.noiseFreq, sum = 0.0, norm = 0.0;
    for (var o = 0; o < 5; o++) {
      sum += amp * _noise(x * freq + 11.3, y * freq + 7.1, z * freq + 3.7);
      norm += amp;
      amp *= 0.5;
      freq *= 2.03;
    }
    return sum / norm;
  }

  /// Planet colour (r, g, b in 0..1) for a surface point.
  List<double> colorAt(double x, double y, double z) {
    final h = height(x, y, z);
    final sea = style.seaLevel;
    List<double> c;
    if (h < sea) {
      final t = (h / sea).clamp(0.0, 1.0);
      c = _lerp(style.deepSea, style.shallowSea, math.pow(t, 1.6).toDouble());
    } else {
      final t = ((h - sea) / (1 - sea)).clamp(0.0, 1.0);
      if (t < 0.5) {
        c = _lerp(style.landLow, style.landMid, t / 0.5);
      } else {
        c = _lerp(style.landMid, style.landHigh, (t - 0.5) / 0.5);
      }
    }
    final ice = ((y.abs() - style.iceStart) / 0.10).clamp(0.0, 1.0).toDouble();
    if (ice > 0) c = _lerp(c, style.ice, ice);
    return c;
  }

  static List<double> _lerp(List<double> a, List<double> b, double t) =>
      [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}
