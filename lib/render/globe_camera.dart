import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import '../core/geometry/vec3.dart';

/// Perspective projection for a viewport. The camera sits on the +Z axis at
/// [distance] looking at the origin; the planet is a unit sphere.
class GlobeProjection {
  GlobeProjection(Size size, this.distance)
      : cx = size.width / 2,
        cy = size.height / 2,
        focal = 1.2 * math.min(size.width, size.height);

  final double cx;
  final double cy;
  final double focal;
  final double distance;

  /// On-screen radius (pixels) of the sphere's silhouette.
  double get radiusPx => focal / math.sqrt(distance * distance - 1);
}

/// Orientation + zoom of the planet as seen by the player.
///
/// The camera never moves around the planet; instead the planet's orientation
/// is a quaternion, which gives free rotation in every direction without
/// gimbal lock. Dragging rotates the sphere under the finger (trackball
/// style), releasing keeps the motion going with inertia.
class GlobeCamera {
  static const double minDistance = 1.7;
  static const double maxDistance = 6.0;
  static const double defaultDistance = 3.4;

  // Orientation quaternion (planet space -> view space).
  double _qw = 1, _qx = 0, _qy = 0, _qz = 0;

  /// Camera distance from planet centre (the "zoom").
  double distance = defaultDistance;

  /// Angular velocity (rad/s) about the view X and Y axes, used for inertia.
  double spinX = 0;
  double spinY = 0;

  // Animated recenter target.
  bool _animating = false;
  double _tw = 1, _tx = 0, _ty = 0, _tz = 0;
  double _targetDistance = defaultDistance;

  /// Row-major 3x3 rotation matrix, planet space -> view space.
  final Float64List matrix = Float64List(9);

  GlobeCamera() {
    _updateMatrix();
  }

  bool get isAnimating => _animating;
  bool get hasInertia => spinX.abs() > 0.015 || spinY.abs() > 0.015;

  GlobeProjection projection(Size size) => GlobeProjection(size, distance);

  // --- Input -----------------------------------------------------------------

  /// Cancels inertia and any recenter animation (call on touch down).
  void grab() {
    spinX = 0;
    spinY = 0;
    _animating = false;
  }

  /// Rotates by a screen-space drag of ([dx], [dy]) pixels so the surface under
  /// the finger follows it.
  void dragBy(double dx, double dy, Size size) {
    final k = 1.0 / projection(size).radiusPx;
    rotateView(dy * k, dx * k, 0);
  }

  /// Rotates the planet by a view-space rotation vector (radians).
  void rotateView(double rx, double ry, double rz) {
    final angle = math.sqrt(rx * rx + ry * ry + rz * rz);
    if (angle < 1e-12) return;
    final s = math.sin(angle / 2) / angle;
    final dw = math.cos(angle / 2);
    final dx = rx * s, dy = ry * s, dz = rz * s;
    // q = dq * q
    final w = dw * _qw - dx * _qx - dy * _qy - dz * _qz;
    final x = dw * _qx + dx * _qw + dy * _qz - dz * _qy;
    final y = dw * _qy - dx * _qz + dy * _qw + dz * _qx;
    final z = dw * _qz + dx * _qy - dy * _qx + dz * _qw;
    _qw = w;
    _qx = x;
    _qy = y;
    _qz = z;
    _normalize();
    _updateMatrix();
  }

  /// Multiplies zoom by [factor] (>1 zooms in).
  void zoomBy(double factor) {
    if (factor <= 0) return;
    distance = (distance / factor).clamp(minDistance, maxDistance).toDouble();
    _animating = false;
  }

  /// Smoothly rotates so the planet-space direction [p] faces the viewer and
  /// returns to the default zoom.
  void focusOn(Vec3 p) {
    // Current view-space position of p.
    final vx = matrix[0] * p.x + matrix[1] * p.y + matrix[2] * p.z;
    final vy = matrix[3] * p.x + matrix[4] * p.y + matrix[5] * p.z;
    final vz = matrix[6] * p.x + matrix[7] * p.y + matrix[8] * p.z;
    // Shortest-arc rotation from v to +Z: axis = v x z, angle = acos(vz).
    var ax = vy, ay = -vx; // v x (0,0,1) = (vy, -vx, 0)
    final len = math.sqrt(ax * ax + ay * ay);
    double dw, dx, dy;
    if (len < 1e-9) {
      if (vz > 0) {
        dw = 1;
        dx = 0;
        dy = 0;
      } else {
        dw = 0; // facing away: half-turn about Y
        dx = 0;
        dy = 1;
      }
    } else {
      final angle = math.atan2(len, vz);
      ax /= len;
      ay /= len;
      final s = math.sin(angle / 2);
      dw = math.cos(angle / 2);
      dx = ax * s;
      dy = ay * s;
    }
    // target = dq * q  (dq has no z component)
    _tw = dw * _qw - dx * _qx - dy * _qy;
    _tx = dw * _qx + dx * _qw + dy * _qz;
    _ty = dw * _qy + dy * _qw - dx * _qz;
    _tz = dw * _qz + dx * _qy - dy * _qx;
    _beginAnimation(defaultDistance);
  }

  /// Smoothly returns to the default orientation and zoom.
  void reset() {
    _tw = 1;
    _tx = 0;
    _ty = 0;
    _tz = 0;
    _beginAnimation(defaultDistance);
  }

  void _beginAnimation(double targetDistance) {
    spinX = 0;
    spinY = 0;
    _targetDistance = targetDistance;
    _animating = true;
    // Take the short way round.
    final dot = _qw * _tw + _qx * _tx + _qy * _ty + _qz * _tz;
    if (dot < 0) {
      _tw = -_tw;
      _tx = -_tx;
      _ty = -_ty;
      _tz = -_tz;
    }
  }

  // --- Per-frame update ------------------------------------------------------

  /// Advances inertia / animation / idle spin by [dt] seconds. Returns true if
  /// the view changed.
  bool tick(double dt, {double idleSpin = 0, bool userHolding = false}) {
    var changed = false;
    if (_animating) {
      final t = 1 - math.exp(-dt * 7.0);
      _qw += (_tw - _qw) * t;
      _qx += (_tx - _qx) * t;
      _qy += (_ty - _qy) * t;
      _qz += (_tz - _qz) * t;
      _normalize();
      distance += (_targetDistance - distance) * t;
      _updateMatrix();
      final err = (_qw - _tw).abs() + (_qx - _tx).abs() + (_qy - _ty).abs() + (_qz - _tz).abs();
      if (err < 1e-4 && (distance - _targetDistance).abs() < 1e-3) {
        _animating = false;
      }
      return true;
    }
    if (!userHolding) {
      if (hasInertia) {
        rotateView(spinX * dt, spinY * dt, 0);
        final decay = math.exp(-dt * 3.2);
        spinX *= decay;
        spinY *= decay;
        changed = true;
      } else {
        spinX = 0;
        spinY = 0;
      }
      if (idleSpin != 0) {
        rotateView(0, idleSpin * dt, 0);
        changed = true;
      }
    }
    return changed;
  }

  // --- Picking ---------------------------------------------------------------

  /// Casts a ray through screen point [p] and returns the planet-space point on
  /// the unit sphere it hits, or null if it misses the planet.
  Vec3? screenToPlanet(Offset p, Size size) {
    final proj = projection(size);
    var dx = (p.dx - proj.cx) / proj.focal;
    var dy = -(p.dy - proj.cy) / proj.focal;
    const dz = -1.0;
    final l = math.sqrt(dx * dx + dy * dy + dz * dz);
    dx /= l;
    dy /= l;
    final dzn = dz / l;
    final d = proj.distance;
    final b = d * dzn; // O . dir with O = (0, 0, d)
    final c = d * d - 1;
    final disc = b * b - c;
    if (disc < 0) return null;
    final t = -b - math.sqrt(disc);
    final hx = t * dx, hy = t * dy, hz = d + t * dzn;
    // Rotate back to planet space with the transpose of the matrix.
    return Vec3(
      matrix[0] * hx + matrix[3] * hy + matrix[6] * hz,
      matrix[1] * hx + matrix[4] * hy + matrix[7] * hz,
      matrix[2] * hx + matrix[5] * hy + matrix[8] * hz,
    );
  }

  // --- Internals -------------------------------------------------------------

  void _normalize() {
    final l = math.sqrt(_qw * _qw + _qx * _qx + _qy * _qy + _qz * _qz);
    if (l == 0) {
      _qw = 1;
      _qx = _qy = _qz = 0;
      return;
    }
    _qw /= l;
    _qx /= l;
    _qy /= l;
    _qz /= l;
  }

  void _updateMatrix() {
    final w = _qw, x = _qx, y = _qy, z = _qz;
    final xx = x * x, yy = y * y, zz = z * z;
    final xy = x * y, xz = x * z, yz = y * z;
    final wx = w * x, wy = w * y, wz = w * z;
    matrix[0] = 1 - 2 * (yy + zz);
    matrix[1] = 2 * (xy - wz);
    matrix[2] = 2 * (xz + wy);
    matrix[3] = 2 * (xy + wz);
    matrix[4] = 1 - 2 * (xx + zz);
    matrix[5] = 2 * (yz - wx);
    matrix[6] = 2 * (xz - wy);
    matrix[7] = 2 * (yz + wx);
    matrix[8] = 1 - 2 * (xx + yy);
  }
}
