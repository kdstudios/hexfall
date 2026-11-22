import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/game/game_engine.dart';
import '../../render/globe_controller.dart';
import '../../theme/hexfall_theme.dart';

/// Flat surface map of the planet (like the corner panels in the concept art):
/// every tile as a dot coloured by its state, plus a marker showing where the
/// camera is looking.
class MiniMap extends StatelessWidget {
  const MiniMap({super.key, required this.controller, this.width = 176});

  final GlobeController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final inner = width - 20;
    return CustomPaint(
      painter: _Brackets(),
      child: Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SURFACE MAP', style: TextStyle(fontSize: 9, letterSpacing: 2, color: HexfallTheme.textDim)),
          const SizedBox(height: 4),
          SizedBox(
            width: inner,
            height: inner / 2,
            child: RepaintBoundary(child: CustomPaint(painter: _MapPainter(controller))),
          ),
        ],
      ),
    ));
  }
}

/// Four glowing corner brackets instead of a full box.
class _Brackets extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = HexfallTheme.cyan.withAlpha(200);
    const l = 14.0;
    final w = size.width, h = size.height;
    canvas.drawPath(Path()..moveTo(0, l)..lineTo(0, 0)..lineTo(l, 0), p);
    canvas.drawPath(Path()..moveTo(w - l, 0)..lineTo(w, 0)..lineTo(w, l), p);
    canvas.drawPath(Path()..moveTo(0, h - l)..lineTo(0, h)..lineTo(l, h), p);
    canvas.drawPath(Path()..moveTo(w - l, h)..lineTo(w, h)..lineTo(w, h - l), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.c) : super(repaint: Listenable.merge([c.mapTick, c.frame]));

  final GlobeController c;

  Object? _grid;
  Float32List _norm = Float32List(0);
  int _version = -1;
  Size? _size;
  final List<Float32List> _lists = List.generate(4, (_) => Float32List(0));

  static const _colors = [
    Color(0xFF5BC8F0), // hidden
    Color(0xFF16404E), // revealed
    Color(0xFF3D8BFF), // flagged
    Color(0xFFFF4A3A), // mine
  ];

  void _rebuild(Size size) {
    final g = c.grid;
    if (_grid != g) {
      _grid = g;
      _norm = Float32List(g.cellCount * 2);
      for (var i = 0; i < g.cellCount; i++) {
        final x = g.centers[i * 3], y = g.centers[i * 3 + 1], z = g.centers[i * 3 + 2];
        final lon = math.atan2(x, z);
        final lat = math.asin(y.clamp(-1.0, 1.0));
        _norm[i * 2] = (lon / math.pi + 1) / 2;
        _norm[i * 2 + 1] = 0.5 - lat / math.pi;
      }
      _version = -1;
    }
    if (_version == c.mapTick.value && _size == size) return;
    _version = c.mapTick.value;
    _size = size;
    final buckets = List.generate(4, (_) => <double>[]);
    final e = c.engine;
    for (var i = 0; i < g.cellCount; i++) {
      var k = 0;
      if (e != null) {
        final st = c.shown[i];
        if (st == CellCode.revealed) {
          k = 1;
        } else if (st == CellCode.flagged) {
          k = 2;
        } else if (st == CellCode.mineRevealed || st == CellCode.exploded) {
          k = 3;
        }
      }
      buckets[k]
        ..add(_norm[i * 2] * size.width)
        ..add(_norm[i * 2 + 1] * size.height);
    }
    for (var k = 0; k < 4; k++) {
      _lists[k] = Float32List.fromList(buckets[k]);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _rebuild(size);
    final g = c.grid;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x99030A14));
    final grid = Paint()
      ..strokeWidth = 0.7
      ..color = HexfallTheme.cyan.withAlpha(40);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), grid);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), grid);

    final dot = math.max(1.8, math.sqrt(size.width * size.height / g.cellCount) * 1.05);
    for (var k = 0; k < 4; k++) {
      if (_lists[k].isEmpty) continue;
      canvas.drawRawPoints(
        ui.PointMode.points,
        _lists[k],
        Paint()
          ..color = _colors[k]
          ..strokeWidth = k == 0 ? dot : dot * 1.15
          ..strokeCap = StrokeCap.square,
      );
    }

    // Where the camera is looking: planet-space direction facing the viewer.
    final m = c.camera.matrix;
    final lon = math.atan2(m[6], m[8]);
    final lat = math.asin(m[7].clamp(-1.0, 1.0));
    final mx = (lon / math.pi + 1) / 2 * size.width;
    final my = (0.5 - lat / math.pi) * size.height;
    final mark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = HexfallTheme.amber;
    canvas.drawCircle(Offset(mx, my), 6, mark);
    canvas.drawLine(Offset(mx - 10, my), Offset(mx + 10, my), mark);
    canvas.drawLine(Offset(mx, my - 10), Offset(mx, my + 10), mark);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = HexfallTheme.cyan.withAlpha(110),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.c != c;
}
