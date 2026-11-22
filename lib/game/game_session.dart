import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/game/game_config.dart';
import '../core/game/game_engine.dart';
import '../core/game/medals.dart';
import '../core/planet/planet_environment.dart';
import '../persistence/app_state.dart';
import '../render/globe_controller.dart';
import '../services/audio_service.dart';
import '../services/haptics.dart';

enum InputMode { reveal, flag }

/// One playthrough of one planet: owns the engine, drives the globe visuals,
/// keeps the clock, plays sounds, autosaves and records the result.
class GameSession extends ChangeNotifier {
  GameSession({
    required this.app,
    required this.globe,
    required this.audio,
    required this.haptics,
    this.clock,
  });

  final AppState app;
  final GlobeController globe;
  final AudioService audio;
  final Haptics haptics;

  /// Injectable time source (tests).
  final DateTime Function()? clock;

  late GameConfig config;
  late GameEngine engine;
  PlanetAppearance get appearance => globe.appearance;

  InputMode mode = InputMode.reveal;
  bool paused = false;
  bool started = false; // first action taken => clock running
  bool showResults = false;
  FinishedGame? result;
  RecordOutcome? recordOutcome;

  final Stopwatch _watch = Stopwatch();
  int _baseMs = 0;
  Timer? _resultTimer;
  bool _disposed = false;

  int get elapsedMs => _baseMs + _watch.elapsedMilliseconds;
  bool get isOver => engine.isOver;
  DateTime _now() => (clock ?? DateTime.now)();

  // ---------------------------------------------------------------------------
  // Creation
  // ---------------------------------------------------------------------------

  /// Random planet for Quick Play.
  static GameConfig randomConfig({
    required Difficulty difficulty,
    int? frequency,
    double? density,
    PlanetEnvironment? environment,
    PlanetAnomaly? anomaly,
    int? seed,
  }) {
    final rnd = math.Random();
    return GameConfig(
      frequency: frequency ?? difficulty.frequency,
      mineDensity: density ?? difficulty.density,
      seed: seed ?? (1 + rnd.nextInt(0x7FFFFFFE)),
      environment: environment ?? PlanetEnvironment.values[rnd.nextInt(PlanetEnvironment.values.length)],
      anomaly: anomaly ?? (rnd.nextInt(3) == 0 ? PlanetAnomaly.values[1 + rnd.nextInt(4)] : PlanetAnomaly.none),
      difficulty: difficulty,
      mode: GameMode.quick,
    );
  }

  void startNew(GameConfig c) {
    _resultTimer?.cancel();
    config = c;
    globe.loadPlanet(
      frequency: c.frequency,
      environment: c.environment,
      seed: c.seed,
      anomaly: c.anomaly,
    );
    engine = GameEngine(globe.grid, c);
    globe.attachEngine(engine);
    globe.camera.reset();
    mode = InputMode.reveal;
    paused = false;
    started = false;
    showResults = false;
    result = null;
    recordOutcome = null;
    _baseMs = 0;
    _watch
      ..stop()
      ..reset();
    notifyListeners();
    unawaited(_save());
  }

  /// Restores the unfinished game stored in [AppState]. Returns false if the
  /// save is missing or unusable.
  bool resumeSaved() {
    final snap = app.savedGame;
    if (snap == null) return false;
    try {
      final engineJson = (snap['engine'] as Map).cast<String, Object?>();
      final c = GameConfig.fromJson((engineJson['config'] as Map).cast<String, Object?>());
      globe.loadPlanet(
        frequency: c.frequency,
        environment: c.environment,
        seed: c.seed,
        anomaly: c.anomaly,
      );
      final e = GameEngine.restore(globe.grid, engineJson);
      if (e == null || e.isOver) return false;
      config = c;
      engine = e;
      globe.attachEngine(e);
      _baseMs = snap['elapsedMs'] as int? ?? 0;
      started = snap['started'] as bool? ?? _baseMs > 0;
      mode = (snap['mode'] as int? ?? 0) == 1 ? InputMode.flag : InputMode.reveal;
      paused = true; // always resume paused so the player is ready
      showResults = false;
      result = null;
      _watch
        ..stop()
        ..reset();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  void setMode(InputMode m) {
    if (mode == m) return;
    mode = m;
    audio.play(Sfx.click);
    notifyListeners();
  }

  /// Primary action (tap / left click) follows the current mode.
  void tapCell(int cell) {
    if (mode == InputMode.reveal) {
      _reveal(cell);
    } else {
      _flag(cell);
    }
  }

  /// Secondary action (long press / right click) is the opposite of the mode.
  void secondaryCell(int cell) {
    if (mode == InputMode.reveal) {
      _flag(cell);
    } else {
      _reveal(cell);
    }
  }

  /// Public entry points used by the touch hold menu.
  void revealCell(int cell) => _reveal(cell);
  void flagCell(int cell) => _flag(cell);

  /// What a touch-and-hold on [cell] should offer right now.
  HoldMenuKind holdKind(int cell) {
    if (paused || engine.isOver) return HoldMenuKind.none;
    final s = engine.state[cell];
    if (s == CellCode.hidden) return HoldMenuKind.hidden;
    if (s == CellCode.flagged) return HoldMenuKind.flagged;
    if (s == CellCode.revealed && engine.counts[cell] > 0) return HoldMenuKind.number;
    return HoldMenuKind.none;
  }

  void _startClock() {
    if (!started) {
      started = true;
      _watch.start();
    }
  }

  void _reveal(int cell) {
    if (paused || engine.isOver) return;
    final out = engine.activate(cell);
    if (out.isEmpty) return;
    _startClock();

    if (out.won) {
      audio.play(Sfx.victory);
      haptics.heavy();
    } else if (out.exploded) {
      audio.play(Sfx.explosion);
      haptics.heavy();
      if (!globe.reducedMotion) {
        // Chain reaction: a rolling series of blasts while the mines go off.
        for (var i = 1; i <= 9; i++) {
          Timer(Duration(milliseconds: 260 * i), () {
            if (!_disposed) audio.play(Sfx.explosion);
          });
        }
      }
    } else if (out.shieldActivated) {
      audio.play(Sfx.explosion);
      audio.play(Sfx.shield);
      haptics.heavy();
    } else if (out.revealed.length > 6) {
      audio.play(Sfx.scan);
      haptics.light();
    } else {
      audio.play(Sfx.reveal);
      haptics.light();
    }

    globe.applyOutcome(out);
    notifyListeners();
    if (engine.isOver) {
      _finish();
    } else {
      unawaited(_save());
    }
  }

  void _flag(int cell) {
    if (paused || engine.isOver) return;
    final wasFlagged = engine.state[cell] == CellCode.flagged;
    if (!engine.toggleFlag(cell)) return;
    _startClock();
    audio.play(wasFlagged ? Sfx.unflag : Sfx.flag);
    haptics.medium();
    globe.applyFlag(cell);
    notifyListeners();
    unawaited(_save());
  }

  // ---------------------------------------------------------------------------
  // Pause / restart
  // ---------------------------------------------------------------------------

  void pause() {
    if (paused || engine.isOver) return;
    paused = true;
    if (_watch.isRunning) {
      _baseMs += _watch.elapsedMilliseconds;
      _watch
        ..stop()
        ..reset();
    }
    notifyListeners();
    unawaited(_save());
  }

  void resume() {
    if (!paused) return;
    paused = false;
    if (started && !engine.isOver) _watch.start();
    notifyListeners();
  }

  /// New random planet of the same kind, or the identical planet again.
  void restart({bool sameSeed = false}) {
    GameConfig next = config;
    if (!sameSeed) {
      switch (config.mode) {
        case GameMode.quick:
          next = randomConfig(
            difficulty: config.difficulty,
            frequency: config.frequency,
            density: config.mineDensity,
          );
        case GameMode.campaign:
        case GameMode.daily:
          next = config; // fixed planets can only be replayed
      }
    }
    startNew(next);
  }

  /// Call when leaving the screen / app is backgrounded.
  Future<void> flushSave() async {
    if (engine.isOver) return;
    if (_watch.isRunning) {
      // Keep the clock running but persist the up-to-date time.
    }
    await _save();
  }

  // ---------------------------------------------------------------------------
  // Finish & persistence
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (engine.isOver || _disposed) return;
    await app.saveGame({
      'engine': engine.toJson(),
      'elapsedMs': elapsedMs,
      'started': started,
      'mode': mode.index,
    });
  }

  void _finish() {
    _baseMs = elapsedMs;
    _watch
      ..stop()
      ..reset();
    final won = engine.status == GameStatus.won;
    var discovered = 0;
    for (var i = 0; i < engine.mines.length; i++) {
      if (engine.mines[i] == 1 && engine.state[i] == CellCode.flagged) discovered++;
    }
    if (won && engine.shieldUsed) discovered++;
    final medal = MedalRules.evaluate(
      won: won,
      shieldUsed: engine.shieldUsed,
      incorrectFlags: engine.incorrectFlags,
      elapsedMs: _baseMs,
      config: config,
    );
    final fin = FinishedGame(
      config: config,
      planetName: appearance.name,
      won: won,
      elapsedMs: _baseMs,
      percentCleared: engine.percentCleared,
      shieldUsed: engine.shieldUsed,
      incorrectFlags: engine.incorrectFlags,
      minesDiscovered: discovered,
      medal: medal,
    );
    result = fin;
    // Record immediately (so a crash during the animation loses nothing),
    // show the results screen once the animation has had time to play.
    unawaited(app.recordFinished(fin, now: _now()).then((o) {
      recordOutcome = o;
      if (!_disposed) notifyListeners();
    }));
    final delay = globe.reducedMotion ? 600 : (won ? 2400 : 4600);
    _resultTimer = Timer(Duration(milliseconds: delay), () {
      showResults = true;
      if (!_disposed) notifyListeners();
    });
    if (!won) audio.play(Sfx.defeat);
    notifyListeners();
  }

  /// Hide the results panel so the player can look around the planet.
  void inspectPlanet() {
    showResults = false;
    notifyListeners();
  }

  void reopenResults() {
    if (result != null) {
      showResults = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _resultTimer?.cancel();
    super.dispose();
  }
}
