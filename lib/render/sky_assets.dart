import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The backdrop art pack (nebulae, gas giants, rings, star layers).
///
/// Everything is optional: if any file fails to load the sky simply leaves
/// that element out, and if the nebula or star layers are missing the planet
/// painter falls back to its own procedural backdrop.
class SkyAssets {
  SkyAssets._();

  static const int nebulaCount = 5;
  static const int giantCount = 4;
  static const int ringCount = 3;
  static const int starCount = 2;

  /// Angle (radians) of each ring picture's major axis, used to split the
  /// ring into the half behind the planet and the half in front.
  static const List<double> ringTilt = [-0.01, 0.03, -0.11];

  static final List<ui.Image?> nebulae = List.filled(nebulaCount, null);
  static final List<ui.Image?> giants = List.filled(giantCount, null);
  static final List<ui.Image?> rings = List.filled(ringCount, null);
  static final List<ui.Image?> stars = List.filled(starCount, null);

  static Future<void>? _loading;
  static bool _done = false;

  /// True once loading has finished and at least a nebula or a star layer exists.
  static bool get ready => _done && (nebulae.any((i) => i != null) || stars.any((i) => i != null));

  static Future<void> load() => _loading ??= _loadAll();

  static Future<void> _loadAll() async {
    Future<void> one(List<ui.Image?> into, int i, String name) async {
      try {
        final data = await rootBundle.load('assets/backgrounds/$name.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        into[i] = frame.image;
        codec.dispose();
      } catch (e) {
        debugPrint('SkyAssets: $name failed to load: $e');
      }
    }

    final jobs = <Future<void>>[
      for (var i = 0; i < nebulaCount; i++) one(nebulae, i, 'nebula${i + 1}'),
      for (var i = 0; i < giantCount; i++) one(giants, i, 'giant${i + 1}'),
      for (var i = 0; i < ringCount; i++) one(rings, i, 'ring${i + 1}'),
      for (var i = 0; i < starCount; i++) one(stars, i, 'stars${i + 1}'),
    ];
    await Future.wait(jobs);
    _done = true;
  }
}
