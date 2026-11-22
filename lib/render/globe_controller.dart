import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter/foundation.dart';

import '../core/game/game_engine.dart';
import '../core/geometry/geodesic_grid.dart';
import '../core/geometry/grid_validator.dart';
import '../core/planet/planet_environment.dart';
import '../persistence/models.dart';
import '../theme/hexfall_theme.dart';
import 'globe_camera.dart';
import 'globe_renderer.dart';
import 'glyph_cache.dart';
import 'tile_atlas.dart';
import 'planet_surface.dart';

class GlobeStats {
  const GlobeStats({this.fps = 0, this.paintMs = 0, this.visibleCells = 0});

  final double fps;
  final double paintMs;
  final int visibleCells;
}

class _Pending {
  _Pending(this.time, this.cell, this.code, this.kind);
  final double time;
  final int cell;
  final int code;
  final int kind;
}

/// What a touch-and-hold on a tile can do.
enum HoldMenuKind { none, hidden, flagged, number }

/// The "hold a tile, then drag up to Reveal / down to Flag" menu.
class HoldMenu {
  HoldMenu({
    required this.cell,
    required this.anchor,
    required this.kind,
    required this.distance,
    required this.cellRadius,
    required this.start,
  });

  final int cell;

  /// Screen position of the tile centre when the menu opened.
  final Offset anchor;
  final HoldMenuKind kind;

  /// How far above / below the tile the two options sit (pixels).
  final double distance;
  final double cellRadius;
  final double start;

  /// -1 = Reveal (up) highlighted, 1 = Flag (down) highlighted, 0 = none.
  int highlight = 0;
}

class Explosion {
  Explosion(this.cell, this.start);
  final int cell;
  final double start;
}

/// Owns everything about the globe that is not drawing or gesture code: the
/// geodesic grid, renderer, camera, visual tile states, effect timelines and
/// view options. The UI listens to this; the painter listens to it and [frame].
class GlobeController extends ChangeNotifier {
  GlobeController({
    int frequency = 8,
    int seed = 20261120,
    PlanetEnvironment environment = PlanetEnvironment.oceanic,
  }) {
    _appearance = PlanetAppearance.generate(environment, seed);
    glyphs = GlyphCache(_palette, onReady: _repaint);
    TileAtlas.load().then((_) {
      if (!_disposed) _repaint();
    });
    _build(frequency);
  }

  final GlobeCamera camera = GlobeCamera();

  /// Bumped every animated frame; the painter repaints on it.
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  final ValueNotifier<GlobeStats> stats = ValueNotifier<GlobeStats>(const GlobeStats());

  late GeodesicGrid grid;
  late GlobeRenderer renderer;
  late GridValidationReport report;
  late PlanetAppearance _appearance;
  Float32List _terrain = Float32List(0);

  PlanetAppearance get appearance => _appearance;
  PlanetAnomaly anomaly = PlanetAnomaly.none;

  // --- Sandbox state -------------------------------------------------------------
  int selected = -1;
  int hovered = -1;
  final Set<int> marked = <int>{};
  bool showPentagons = false;

  // --- View options --------------------------------------------------------------
  bool scanEffect = true;
  bool autoRotate = false;
  bool outlineGlow = true;
  bool anomalyEffects = true;
  bool reducedMotion = false;
  late GlyphCache glyphs;
  NumberPalette _palette = NumberPalette.standard;

  // Quality: the user's choice, plus an automatic fallback when frames are slow.
  RenderQuality _userQuality = RenderQuality.auto;
  int autoLevel = 2; // only ever lowered while in Auto mode
  int _lowFpsWindows = 0;
  bool _scanSetting = true;
  double hiddenTint = Settings.defaultHiddenTint;
  double scannedTint = Settings.defaultScannedTint;
  bool depthWalls = true;
  bool depthEdges = true;
  bool depthRelief = true;

  /// 0 = low, 1 = medium, 2 = high.
  int get qualityLevel => switch (_userQuality) {
        RenderQuality.low => 0,
        RenderQuality.medium => 1,
        RenderQuality.high => 2,
        RenderQuality.auto => autoLevel,
      };

  // Reveal pulse (a bright ring sweeping over the surface).
  double pulseStart = -100;

  /// Chain-detonation window after a fatal mine (time-based, visual only).
  double cascadeStart = -100;
  double cascadeEnd = -100;
  double pulseX = 0, pulseY = 0, pulseZ = 1;
  double pulseStrength = 0;

  /// Bumped when tile states change (drives the mini-map).
  final ValueNotifier<int> mapTick = ValueNotifier<int>(0);

  bool _disposed = false;

  void _repaint() {
    if (!_disposed) frame.value++;
  }

  // --- Game visual state -----------------------------------------------------------
  GameEngine? engine;
  Uint8List shown = Uint8List(0);
  Uint8List incorrect = Uint8List(0);
  Float32List flashStart = Float32List(0);
  Uint8List flashKind = Uint8List(0);
  final List<_Pending> _pending = [];
  int _pendingHead = 0;

  // --- Effect timelines (seconds on the controller clock) ---------------------------
  double time = 0;
  double generationMs = 0;
  double shieldPulseStart = -100;
  double shakeStart = -100;
  double destructStart = -100;
  double victoryStart = -100;
  double hitFlashStart = -100;
  final List<Explosion> explosions = [];

  /// Non-null while the touch hold menu is open.
  HoldMenu? holdMenu;

  int get frequency => grid.frequency;
  bool get hasEngine => engine != null;

  // ===========================================================================
  // Planet / grid
  // ===========================================================================

  /// Switches to another planet. Rebuilds the grid only if the frequency changes.
  void loadPlanet({
    required int frequency,
    required PlanetEnvironment environment,
    required int seed,
    PlanetAnomaly anomaly = PlanetAnomaly.none,
  }) {
    this.anomaly = anomaly;
    _appearance = PlanetAppearance.generate(environment, seed);
    if (frequency != grid.frequency) {
      _build(frequency);
    } else {
      _resetVisualState();
      _terrain = _paintTerrain();
      _recolorAll();
    }
    notifyListeners();
    frame.value++;
  }

  void setFrequency(int frequency) {
    if (frequency == grid.frequency) return;
    _build(frequency);
    notifyListeners();
  }

  void _build(int frequency) {
    final watch = Stopwatch()..start();
    grid = GeodesicGrid.generate(frequency);
    renderer = GlobeRenderer(grid);
    _terrain = _paintTerrain();
    _resetVisualState();
    report = GridValidator.validate(grid);
    _recolorAll();
    watch.stop();
    generationMs = watch.elapsedMicroseconds / 1000.0;
  }

  void _resetVisualState() {
    final n = grid.cellCount;
    engine = null;
    selected = -1;
    hovered = -1;
    marked.clear();
    shown = Uint8List(n);
    incorrect = Uint8List(n);
    flashStart = Float32List(n)..fillRange(0, n, -100);
    flashKind = Uint8List(n);
    _pending.clear();
    _pendingHead = 0;
    explosions.clear();
    shieldPulseStart = shakeStart = destructStart = victoryStart = hitFlashStart = -100;
    pulseStart = -100;
    cascadeStart = cascadeEnd = -100;
  }

  Float32List _paintTerrain() {
    final surface = PlanetSurface(_appearance.seed, _appearance.style);
    final out = Float32List(grid.cellCount * 3);
    for (var c = 0; c < grid.cellCount; c++) {
      final i = c * 3;
      final rgb = surface.colorAt(grid.centers[i], grid.centers[i + 1], grid.centers[i + 2]);
      out[i] = rgb[0];
      out[i + 1] = rgb[1];
      out[i + 2] = rgb[2];
    }
    return out;
  }

  // ===========================================================================
  // Game attachment & visual sync
  // ===========================================================================

  /// Starts showing [e]. All tiles appear in their current logical state at once
  /// (used for new games and for resuming saved ones).
  void attachEngine(GameEngine e) {
    engine = e;
    _pending.clear();
    _pendingHead = 0;
    explosions.clear();
    final n = grid.cellCount;
    shown = Uint8List.fromList(e.state);
    incorrect = Uint8List(n);
    flashStart.fillRange(0, n, -100);
    shieldPulseStart = shakeStart = destructStart = victoryStart = hitFlashStart = -100;
    cascadeStart = cascadeEnd = -100;
    selected = -1;
    hovered = -1;
    if (e.status == GameStatus.lost) _markIncorrectFlags();
    _recolorAll();
    mapTick.value++;
    notifyListeners();
    frame.value++;
  }

  void detachEngine() {
    engine = null;
    shown = Uint8List(grid.cellCount);
    _pending.clear();
    _pendingHead = 0;
    _recolorAll();
    mapTick.value++;
  }

  void _markIncorrectFlags() {
    final e = engine!;
    for (var i = 0; i < e.state.length; i++) {
      incorrect[i] = (e.state[i] == CellCode.flagged && e.mines[i] == 0) ? 1 : 0;
    }
  }

  /// Visual response to a player action. Logical state is already final.
  void applyOutcome(RevealOutcome o) {
    final e = engine;
    if (e == null) return;
    final now = time;

    // Scan wave: stagger by flood depth.
    var maxDepth = 0;
    for (final d in o.depths) {
      if (d > maxDepth) maxDepth = d;
    }
    final step = reducedMotion ? 0.0 : (maxDepth == 0 ? 0.0 : math.min(0.045, 1.3 / maxDepth));
    for (var i = 0; i < o.revealed.length; i++) {
      _pending.add(_Pending(now + o.depths[i] * step, o.revealed[i], CellCode.revealed, 0));
    }

    if (o.revealed.isNotEmpty && !reducedMotion) {
      final origin = grid.centerOf(o.revealed.first);
      pulseStart = now;
      pulseX = origin.x;
      pulseY = origin.y;
      pulseZ = origin.z;
      pulseStrength = math.min(1.0, 0.55 + o.revealed.length / 60.0);
    }

    for (final hit in o.mineHits) {
      _pending.add(_Pending(now, hit, e.state[hit], 1));
      explosions.add(Explosion(hit, now));
    }
    if (o.mineHits.isNotEmpty) hitFlashStart = now;

    if (o.shieldActivated) shieldPulseStart = now;

    if (o.exploded) {
      _markIncorrectFlags();
      _startChainDetonation(e, o, now);
    }

    // The pending list is consumed in time order.
    if (_pending.length - _pendingHead > 1) {
      final tail = _pending.sublist(_pendingHead)..sort((x, y) => x.time.compareTo(y.time));
      _pending
        ..removeRange(_pendingHead, _pending.length)
        ..addAll(tail);
    }

    if (o.won) startVictory(o.revealed.isNotEmpty ? o.revealed.last : 0);
    _recolorAll();
    notifyListeners();
    frame.value++;
  }

  /// The fatal mine sets off every other mine on the planet: a chain reaction
  /// that races outward from the first blast (nearest mines first, with a
  /// little jitter so it feels like fuses burning, not a perfect ring), then
  /// the whole world shudders. Purely visual; the logical state is already final.
  void _startChainDetonation(GameEngine e, RevealOutcome o, double now) {
    final origin = grid.centerOf(o.mineHits.isNotEmpty ? o.mineHits.last : 0);
    final order = <(int, double)>[];
    for (var c = 0; c < grid.cellCount; c++) {
      if (e.mines[c] == 1 &&
          e.state[c] == CellCode.mineRevealed &&
          shown[c] != CellCode.mineRevealed &&
          !o.mineHits.contains(c)) {
        final ang = math.acos(grid.centerOf(c).dot(origin).clamp(-1.0, 1.0));
        order.add((c, ang));
      }
    }
    order.sort((x, y) => x.$2.compareTo(y.$2));
    final m = order.length;
    final total = reducedMotion ? 0.0 : (1.0 + m * 0.01).clamp(1.4, 2.6).toDouble();
    final maxAng = m == 0 ? 1.0 : math.max(0.001, order.last.$2);
    final stride = math.max(1, m ~/ 110); // cap the number of fireballs drawn
    var last = now + 0.3;
    for (var i = 0; i < m; i++) {
      final c = order[i].$1;
      final frac = 0.6 * (order[i].$2 / maxAng) + 0.4 * (i / m);
      final jitter = reducedMotion ? 0.0 : (((c * 2654435761) & 0xFFFF) / 65535.0) * 0.07;
      final t = now + 0.3 + total * math.pow(frac, 0.85).toDouble() + jitter;
      if (t > last) last = t;
      _pending.add(_Pending(t, c, CellCode.mineRevealed, 1));
      if (!reducedMotion && i % stride == 0) explosions.add(Explosion(c, t));
    }
    shakeStart = now;
    cascadeStart = now + 0.3;
    cascadeEnd = last;
    destructStart = last - 0.1;
  }

  /// A flag was placed or removed on [cell].
  void applyFlag(int cell) {
    final e = engine;
    if (e == null) return;
    shown[cell] = e.state[cell];
    _recolorCell(cell);
    mapTick.value++;
    frame.value++;
  }

  void startVictory(int origin) {
    final now = time;
    victoryStart = now;
    final o = grid.centerOf(origin);
    for (var c = 0; c < grid.cellCount; c++) {
      final p = grid.centerOf(c);
      final angle = math.acos(p.dot(o).clamp(-1.0, 1.0));
      flashStart[c] = now + (reducedMotion ? 0 : angle * 0.55);
      flashKind[c] = 2;
    }
  }

  /// Per-frame update; returns true if visuals changed.
  bool update() {
    var changed = false;
    while (_pendingHead < _pending.length && _pending[_pendingHead].time <= time) {
      final p = _pending[_pendingHead++];
      shown[p.cell] = p.code;
      flashStart[p.cell] = p.time;
      flashKind[p.cell] = p.kind;
      _recolorCell(p.cell);
      changed = true;
      mapTick.value++;
    }
    if (_pendingHead > 0 && _pendingHead == _pending.length) {
      _pending.clear();
      _pendingHead = 0;
    }
    if (explosions.isNotEmpty) {
      explosions.removeWhere((x) => time - x.start > 1.2);
      changed = true;
    }
    return changed;
  }

  /// True while anything time-based is playing (keeps the ticker repainting).
  bool get hasActiveEffects =>
      _pending.length > _pendingHead ||
      explosions.isNotEmpty ||
      time - shieldPulseStart < 1.4 ||
      time - shakeStart < 1.0 ||
      time - destructStart < 3.0 ||
      time < cascadeEnd + 1.5 ||
      time - victoryStart < 6.0 ||
      time - hitFlashStart < 0.6 ||
      time - pulseStart < 1.8 ||
      (anomalyEffects && anomaly != PlanetAnomaly.none && !reducedMotion);

  /// Screen-shake amplitude in pixels: a kick on the fatal hit, a rumble that
  /// builds through the chain detonation, and a final slam when it ends.
  double get shakeAmplitude {
    if (reducedMotion) return 0;
    var a = 0.0;
    final k0 = time - shakeStart;
    if (k0 >= 0 && k0 < 1.0) a += 9.0 * math.exp(-k0 * 5.0);
    if (time >= cascadeStart && time < cascadeEnd) {
      final k = (time - cascadeStart) / math.max(0.01, cascadeEnd - cascadeStart);
      a += 1.5 + 4.5 * k;
    }
    final k1 = time - cascadeEnd;
    if (k1 >= 0 && k1 < 1.4) a += 12.0 * math.exp(-k1 * 3.5);
    return a;
  }

  /// Current outward "shock" for the destruction pulse (0 at rest).
  double get destructAmount {
    if (reducedMotion) return 0;
    final age = time - destructStart;
    if (age < 0 || age > 3.0) return 0;
    final rise = math.sin(math.min(age / 0.3, 1.0) * math.pi / 2);
    return 0.28 * rise * math.exp(-age * 1.7);
  }

  // ===========================================================================
  // Colours
  // ===========================================================================

  void _recolorAll() {
    for (var c = 0; c < grid.cellCount; c++) {
      _recolorCell(c);
    }
  }

  void _recolorCell(int c) {
    final out = renderer.cellRgb;
    final i = c * 3;
    const tint = HexfallTheme.holoTint;
    var r = _terrain[i], g = _terrain[i + 1], b = _terrain[i + 2];

    void mix(List<double> to, double a) {
      r += (to[0] - r) * a;
      g += (to[1] - g) * a;
      b += (to[2] - b) * a;
    }

    void scale(double s) {
      r *= s;
      g *= s;
      b *= s;
    }

    final e = engine;
    if (e == null) {
      mix(tint, HexfallTheme.holoTintAmount);
      if (showPentagons && grid.sidesOf(c) == 5) mix(HexfallTheme.pentagonColor, 0.55);
      if (marked.contains(c)) mix(HexfallTheme.markedColor, 0.60);
      if (selected >= 0) {
        for (var k = grid.cellOffsets[selected]; k < grid.cellOffsets[selected + 1]; k++) {
          if (grid.neighbourIndices[k] == c) mix(HexfallTheme.neighbourColor, 0.35);
        }
        if (c == selected) mix(HexfallTheme.selectedColor, 0.65);
      }
      if (c == hovered && c != selected) mix(HexfallTheme.hoverColor, 0.35);
    } else {
      // Concept-art look: hidden tiles are dark gunmetal, scanned tiles are
      // near-black with glowing outlines + numbers (drawn by the renderer).
      const gun = [0.13, 0.18, 0.26];
      void toGun(double keepTerrain) {
        r = gun[0] + (r - gun[0]) * keepTerrain;
        g = gun[1] + (g - gun[1]) * keepTerrain;
        b = gun[2] + (b - gun[2]) * keepTerrain;
      }

      switch (shown[c]) {
        case CellCode.revealed:
          scale(e.counts[c] == 0 ? 0.13 : 0.17);
          mix(const [0.01, 0.04, 0.07], 0.55);
        case CellCode.flagged:
          toGun(0.12);
          mix(const [0.10, 0.40, 0.75], 0.40);
        case CellCode.mineRevealed:
          mix(const [0.30, 0.04, 0.05], 0.75);
        case CellCode.exploded:
          mix(const [0.95, 0.25, 0.06], 0.85);
        default: // hidden
          toGun(0.14);
      }
      if (incorrect[c] == 1) mix(const [0.8, 0.1, 0.1], 0.5);
      if (c == hovered && !e.isOver) mix(HexfallTheme.hoverColor, 0.28);
    }
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
  }

  // ===========================================================================
  // Interaction helpers
  // ===========================================================================

  /// Returns the cell under screen point [p], or -1 if the planet is missed.
  int pick(Offset p, Size size) {
    final hit = camera.screenToPlanet(p, size);
    if (hit == null) return -1;
    return grid.cellAt(hit.x, hit.y, hit.z);
  }

  void select(int id) {
    if (id == selected) return;
    selected = id;
    _recolorAll();
    notifyListeners();
  }

  void setHover(int id) {
    if (id == hovered) return;
    final old = hovered;
    hovered = id;
    if (old >= 0) _recolorCell(old);
    if (id >= 0) _recolorCell(id);
    frame.value++;
  }

  /// Sandbox stand-in for flagging.
  void toggleMarker(int id) {
    if (id < 0) return;
    if (!marked.remove(id)) marked.add(id);
    _recolorAll();
    notifyListeners();
  }

  void recenter() {
    if (selected >= 0) {
      camera.focusOn(grid.centerOf(selected));
    } else {
      camera.reset();
    }
    frame.value++;
  }

  /// Rotates the planet so [cell] faces the viewer.
  void focusCell(int cell) {
    camera.focusOn(grid.centerOf(cell));
    frame.value++;
  }

  // ===========================================================================
  // Options
  // ===========================================================================

  void applySettings(Settings s) {
    reducedMotion = s.reducedMotion;
    _userQuality = s.quality;
    _scanSetting = s.scanEffects;
    anomalyEffects = s.anomalyEffects;
    hiddenTint = s.hiddenTint;
    scannedTint = s.scannedTint;
    depthWalls = s.depthWalls;
    depthEdges = s.depthEdges;
    depthRelief = s.depthRelief;
    if (s.reducedMotion) autoRotate = false;
    _applyQuality();
    if (s.palette != _palette) {
      _palette = s.palette;
      glyphs.dispose();
      glyphs = GlyphCache(_palette, onReady: _repaint);
    }
    notifyListeners();
    frame.value++;
  }

  void _applyQuality() {
    scanEffect = _scanSetting && !reducedMotion && qualityLevel >= 1;
  }

  /// Called twice a second with the measured frame rate. In Auto mode the
  /// quality is stepped down (never back up) if frames stay slow.
  void reportFps(double fps) {
    if (_userQuality != RenderQuality.auto || autoLevel == 0 || fps <= 0) return;
    if (fps < 42) {
      _lowFpsWindows++;
    } else {
      _lowFpsWindows = 0;
    }
    if (_lowFpsWindows >= 4) {
      autoLevel--;
      _lowFpsWindows = 0;
      _applyQuality();
      notifyListeners();
    }
  }

  void setShowPentagons(bool v) {
    showPentagons = v;
    _recolorAll();
    notifyListeners();
  }

  void setScanEffect(bool v) {
    scanEffect = v;
    notifyListeners();
    frame.value++;
  }

  void setAutoRotate(bool v) {
    autoRotate = v;
    notifyListeners();
  }

  void setOutlineGlow(bool v) {
    outlineGlow = v;
    notifyListeners();
    frame.value++;
  }

  GlobeRenderOptions renderOptions() {
    final inGame = engine != null;
    var level = qualityLevel;
    if (!outlineGlow && level > 1) level = 1;
    final pulseAge = time - pulseStart;
    const pulseDuration = 1.7;
    final pulseOn = pulseAge >= 0 && pulseAge < pulseDuration && !reducedMotion;
    return GlobeRenderOptions(
      selected: selected,
      hovered: hovered,
      marked: marked,
      time: time,
      scanEffect: scanEffect,
      quality: level,
      shown: inGame ? shown : null,
      counts: inGame ? engine!.counts : null,
      incorrect: inGame ? incorrect : null,
      glyphs: inGame ? glyphs : null,
      flashStart: flashStart,
      flashKind: flashKind,
      destruct: destructAmount,
      outlineColor: _outlineColor(),
      pulseX: pulseX,
      pulseY: pulseY,
      pulseZ: pulseZ,
      pulseFront: pulseAge * 2.6,
      pulseStrength: pulseOn ? pulseStrength * (1 - pulseAge / pulseDuration) : 0,
      numberColors: NumberPalettes.of(_palette),
      tint: _appearance.style.atmosphere,
      terrain: inGame ? _terrain : null,
      terrainStrength: hiddenTint,
      scannedStrength: scannedTint,
      walls: depthWalls,
      edges: depthEdges,
      relief: depthRelief,
    );
  }

  /// Crystal resonance slowly shifts the outline colour; others use the default.
  Color? _outlineColor() {
    if (!anomalyEffects || reducedMotion || anomaly != PlanetAnomaly.crystalResonance) return null;
    final t = time * 0.6;
    return Color.fromARGB(
      255,
      (150 + 90 * math.sin(t)).round(),
      (170 + 60 * math.sin(t + 2.1)).round(),
      255,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    frame.dispose();
    mapTick.dispose();
    stats.dispose();
    glyphs.dispose();
    super.dispose();
  }
}
