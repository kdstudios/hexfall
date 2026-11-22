import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/planet/planet_environment.dart';
import '../../persistence/app_state.dart';
import '../../render/globe_controller.dart';
import '../../render/globe_view.dart';
import '../../render/planet_surface.dart';
import '../../services/audio_service.dart';
import '../../services/sound_library.dart';
import '../../services/haptics.dart';
import '../../theme/hexfall_theme.dart';

/// Everything screens share. Created once in main().
class Services {
  Services({
    required this.app,
    required this.audio,
    required this.haptics,
    required this.sounds,
  })  : menuGlobe = GlobeController(frequency: 6, seed: 4242, environment: PlanetEnvironment.oceanic)
          ..autoRotate = true,
        gameGlobe = GlobeController(frequency: 8) {
    app.addListener(_applySettings);
    _applySettings();
  }

  final AppState app;
  final AudioService audio;
  final Haptics haptics;
  final SoundLibrary sounds;
  final GlobeController menuGlobe;
  final GlobeController gameGlobe;

  void _applySettings() {
    final s = app.settings;
    audio.applySettings(s);
    haptics.enabled = s.haptics;
    gameGlobe.applySettings(s);
    menuGlobe.applySettings(s);
    menuGlobe.autoRotate = !s.reducedMotion;
  }

  void dispose() {
    app.removeListener(_applySettings);
    menuGlobe.dispose();
    gameGlobe.dispose();
    audio.dispose();
  }
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({super.key, required this.services, required super.child});

  final Services services;

  static Services of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) => services != oldWidget.services;
}

// -----------------------------------------------------------------------------

/// Chamfered-corner frame used by every panel (see the menu concept art).
Decoration sciFiDecoration({Color? border, double glow = 0.0, Color? fill}) => ShapeDecoration(
      color: fill ?? HexfallTheme.panel,
      shape: BeveledRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: (border ?? HexfallTheme.cyan).withAlpha(150), width: 1.3),
      ),
      shadows: glow > 0
          ? [BoxShadow(color: (border ?? HexfallTheme.cyan).withAlpha((60 * glow).round()), blurRadius: 18)]
          : null,
    );

class SciFiPanel extends StatelessWidget {
  const SciFiPanel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.border});

  final Widget child;
  final EdgeInsets padding;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: sciFiDecoration(border: border, glow: 1),
        // Transparent Material so ListTile / Switch ink renders on top of the
        // decorated background instead of being hidden by it.
        child: Material(type: MaterialType.transparency, child: child),
      );
}

class SciFiButton extends StatelessWidget {
  const SciFiButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.dense = false,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool dense;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? HexfallTheme.textDim
        : (primary || selected ? HexfallTheme.cyan : HexfallTheme.cyanSoft);
    final services = ServicesScope.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled
            ? () {
                services.audio.ensureStarted();
                services.audio.play(Sfx.click);
                onPressed!();
              }
            : null,
        customBorder: BeveledRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 8 : 13),
          decoration: ShapeDecoration(
            color: (primary || selected) ? HexfallTheme.cyan.withAlpha(36) : const Color(0x990A1A2E),
            shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: color.withAlpha(enabled ? 190 : 70), width: 1.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: dense ? 16 : 20, color: color), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontSize: dense ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menu background: the slowly rotating planet over deep space.
class MenuBackdrop extends StatelessWidget {
  const MenuBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        GlobeView(controller: services.menuGlobe, interactive: false),
        // Darken so menu text is always readable.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x00000000), Color(0x99020611)],
            ),
          ),
        ),
      ],
    );
  }
}

/// Standard menu screen: backdrop, title bar with back button, content.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.title, required this.child, this.actions});

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MenuBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back, color: HexfallTheme.cyan),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            color: HexfallTheme.cyan,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      ...?actions,
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String formatTime(int ms) {
  final totalSeconds = ms ~/ 1000;
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  final t = (ms % 1000) ~/ 100;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$t';
}

// -----------------------------------------------------------------------------

/// A small, static, shaded planet image drawn from the same procedural surface
/// as the real globe (sampled once; no GPU cost afterwards).
class PlanetPreview extends StatefulWidget {
  const PlanetPreview({super.key, required this.environment, required this.seed, this.size = 96});

  final PlanetEnvironment environment;
  final int seed;
  final double size;

  @override
  State<PlanetPreview> createState() => _PlanetPreviewState();
}

class _PlanetPreviewState extends State<PlanetPreview> {
  late _Samples _samples;

  @override
  void initState() {
    super.initState();
    _samples = _Samples.build(widget.environment, widget.seed);
  }

  @override
  void didUpdateWidget(PlanetPreview old) {
    super.didUpdateWidget(old);
    if (old.environment != widget.environment || old.seed != widget.seed) {
      _samples = _Samples.build(widget.environment, widget.seed);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _PreviewPainter(_samples)),
      );
}

class _Samples {
  _Samples(this.colors, this.atmosphere);
  static const int n = 28;
  final List<Color?> colors; // n*n, null outside the disc
  final Color atmosphere;

  static _Samples build(PlanetEnvironment env, int seed) {
    final look = PlanetAppearance.generate(env, seed);
    final surface = PlanetSurface(seed, look.style);
    final tilt = (seed % 360) * math.pi / 180;
    final ct = math.cos(tilt), st = math.sin(tilt);
    final out = List<Color?>.filled(n * n, null);
    for (var iy = 0; iy < n; iy++) {
      for (var ix = 0; ix < n; ix++) {
        final x = (ix + 0.5) / n * 2 - 1;
        final y = -((iy + 0.5) / n * 2 - 1);
        final r2 = x * x + y * y;
        if (r2 > 1) continue;
        final z = math.sqrt(1 - r2);
        // Spin the sample point about the vertical axis for variety.
        final px = x * ct + z * st;
        final pz = -x * st + z * ct;
        final c = surface.colorAt(px, y, pz);
        final lam = math.max(0.0, x * -0.45 + y * 0.5 + z * 0.74);
        final shade = 0.22 + 0.95 * lam;
        out[iy * n + ix] = Color.fromARGB(
          255,
          (c[0] * shade * 255).clamp(0, 255).round(),
          (c[1] * shade * 255).clamp(0, 255).round(),
          (c[2] * shade * 255).clamp(0, 255).round(),
        );
      }
    }
    return _Samples(out, look.style.atmosphere);
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.s);
  final _Samples s;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      r * 1.05,
      Paint()..color = s.atmosphere.withAlpha(60)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final cell = size.shortestSide / _Samples.n;
    final paint = Paint();
    for (var iy = 0; iy < _Samples.n; iy++) {
      for (var ix = 0; ix < _Samples.n; ix++) {
        final c = s.colors[iy * _Samples.n + ix];
        if (c == null) continue;
        paint.color = c;
        canvas.drawRect(Rect.fromLTWH(ix * cell, iy * cell, cell + 0.7, cell + 0.7), paint);
      }
    }
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = s.atmosphere.withAlpha(150),
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.s != s;
}
