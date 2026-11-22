import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/game/game_config.dart';
import 'package:hexfall/core/game/game_engine.dart';
import 'package:hexfall/core/planet/planet_environment.dart';
import 'package:hexfall/persistence/models.dart';
import 'package:hexfall/render/globe_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto quality steps down after sustained slow frames, never up', () {
    final c = GlobeController(frequency: 3)..applySettings(const Settings());
    expect(c.qualityLevel, 2);
    for (var i = 0; i < 3; i++) {
      c.reportFps(20);
    }
    expect(c.qualityLevel, 2); // not yet: needs 4 slow windows in a row
    c.reportFps(20);
    expect(c.qualityLevel, 1);
    c.reportFps(60); // recovery does not raise it again
    expect(c.qualityLevel, 1);
    for (var i = 0; i < 4; i++) {
      c.reportFps(20);
    }
    expect(c.qualityLevel, 0);
    for (var i = 0; i < 8; i++) {
      c.reportFps(5);
    }
    expect(c.qualityLevel, 0);
  });

  test('a single slow window does not trigger a downgrade', () {
    final c = GlobeController(frequency: 3)..applySettings(const Settings());
    c.reportFps(20);
    c.reportFps(60);
    c.reportFps(20);
    c.reportFps(20);
    c.reportFps(20);
    expect(c.qualityLevel, 2);
  });

  test('explicit quality is never changed automatically', () {
    final c = GlobeController(frequency: 3)..applySettings(const Settings(quality: RenderQuality.high));
    for (var i = 0; i < 20; i++) {
      c.reportFps(10);
    }
    expect(c.qualityLevel, 2);
  });

  test('low quality turns the scan effect off', () {
    final c = GlobeController(frequency: 3)..applySettings(const Settings(quality: RenderQuality.low));
    expect(c.scanEffect, isFalse);
    c.applySettings(const Settings(quality: RenderQuality.medium));
    expect(c.scanEffect, isTrue);
  });

  GameEngine engineFor(GlobeController c) {
    const cfg = GameConfig(frequency: 3, mineDensity: 0.1, seed: 11, environment: PlanetEnvironment.oceanic);
    final e = GameEngine(c.grid, cfg);
    c.attachEngine(e);
    return e;
  }

  test('revealing tiles starts the surface pulse', () {
    final c = GlobeController(frequency: 3)..applySettings(const Settings());
    final e = engineFor(c);
    final cell = e.mines.indexOf(0);
    final out = e.reveal(cell);
    c.time = 5;
    c.applyOutcome(out);
    expect(c.pulseStart, 5);
    expect(c.pulseStrength, greaterThanOrEqualTo(0.55));
    c.time = 5.3;
    final o = c.renderOptions();
    expect(o.pulseStrength, greaterThan(0));
    expect(o.pulseFront, closeTo(0.3 * 2.6, 1e-9));
    c.time = 8;
    expect(c.renderOptions().pulseStrength, 0);
  });

  test('reduced motion disables the pulse', () {
    final c = GlobeController(frequency: 3)..applySettings(const Settings(reducedMotion: true));
    final e = engineFor(c);
    final out = e.reveal(e.mines.indexOf(0));
    c.time = 2;
    c.applyOutcome(out);
    c.time = 2.2;
    expect(c.renderOptions().pulseStrength, 0);
  });

  test('revealed tiles are delayed by flood depth, then become visible', () {
    final c = GlobeController(frequency: 4)..applySettings(const Settings());
    final cfg = GameConfig(frequency: 4, mineDensity: 0.04, seed: 3, environment: PlanetEnvironment.verdant);
    final e = GameEngine(c.grid, cfg);
    c.attachEngine(e);
    final zero = List.generate(e.mines.length, (i) => i).firstWhere((i) => e.mines[i] == 0 && e.counts[i] == 0);
    c.time = 1;
    final out = e.reveal(zero);
    c.applyOutcome(out);
    expect(c.shown[zero], CellCode.hidden); // not applied until update() runs
    c.update();
    expect(c.shown[zero], CellCode.revealed);
    c.time = 10;
    c.update();
    for (final cell in out.revealed) {
      expect(c.shown[cell], CellCode.revealed);
    }
  });

  test('settings default to Auto quality', () {
    expect(const Settings().quality, RenderQuality.auto);
    expect(Settings.fromJson(const {}).quality, RenderQuality.auto);
    expect(Settings.fromJson(const {'quality': 2}).quality, RenderQuality.high);
  });

  test('a fatal mine sets off every other mine in a chain', () {
    final c = GlobeController(frequency: 4)..applySettings(const Settings());
    final cfg = GameConfig(frequency: 4, mineDensity: 0.12, seed: 5, environment: PlanetEnvironment.desert);
    final e = GameEngine(c.grid, cfg);
    c.attachEngine(e);
    final mines = [
      for (var i = 0; i < e.mines.length; i++)
        if (e.mines[i] == 1) i,
    ];
    c.time = 1;
    c.applyOutcome(e.reveal(mines[0])); // absorbed by the shield
    c.applyOutcome(e.reveal(mines[1])); // fatal
    expect(e.status, GameStatus.lost);
    expect(c.cascadeEnd, greaterThan(c.cascadeStart));
    c.time = c.cascadeStart + 0.01;
    c.update();
    expect(mines.where((m) => c.shown[m] == CellCode.hidden).isNotEmpty, isTrue); // still going off
    c.time = c.cascadeEnd + 0.1;
    c.update();
    for (final m in mines) {
      expect(c.shown[m] == CellCode.mineRevealed || c.shown[m] == CellCode.exploded, isTrue);
    }
    expect(c.shakeAmplitude, greaterThan(0));
  });

  test('colour strength and depth options default sensibly and survive a save', () {
    const s = Settings();
    expect(s.hiddenTint, 1.0);
    expect(s.scannedTint, 0.6);
    final changed = s.copyWith(hiddenTint: 0.4, scannedTint: 0.9, depthWalls: false);
    final back = Settings.fromJson(changed.toJson());
    expect(back.hiddenTint, 0.4);
    expect(back.scannedTint, 0.9);
    expect(back.depthWalls, isFalse);
    expect(back.depthEdges, isTrue);
    final c = GlobeController(frequency: 3)..applySettings(back);
    expect(c.hiddenTint, 0.4);
    expect(c.renderOptions().scannedStrength, 0.9);
  });
}
