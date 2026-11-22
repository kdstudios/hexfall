import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/game/game_config.dart';
import 'package:hexfall/core/game/game_engine.dart';
import 'package:hexfall/core/game/medals.dart';
import 'package:hexfall/core/planet/planet_environment.dart';
import 'package:hexfall/game/game_session.dart';
import 'package:hexfall/persistence/app_state.dart';
import 'package:hexfall/persistence/key_value_store.dart';
import 'package:hexfall/render/globe_controller.dart';
import 'package:hexfall/services/audio_service.dart';
import 'package:hexfall/services/haptics.dart';

const cfg = GameConfig(
  frequency: 3,
  mineDensity: 0.10,
  seed: 4242,
  environment: PlanetEnvironment.verdant,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GameSession, AppState, MemoryStore)> make() async {
    final store = MemoryStore();
    final app = await AppState.load(store);
    final s = GameSession(
      app: app,
      globe: GlobeController(frequency: 3),
      audio: SilentAudio(),
      haptics: Haptics(enabled: false),
    );
    return (s, app, store);
  }

  int firstMine(GameEngine e) => e.mines.indexOf(1);
  int secondMine(GameEngine e) => e.mines.indexOf(1, firstMine(e) + 1);

  test('new game starts with shield, clock stopped until first action', () async {
    final (s, _, _) = await make();
    s.startNew(cfg);
    expect(s.engine.shieldAvailable, isTrue);
    expect(s.started, isFalse);
    expect(s.elapsedMs, 0);
    s.dispose();
  });

  test('first mine is survived, second mine ends the game and is recorded', () async {
    final (s, app, _) = await make();
    s.startNew(cfg);
    s.tapCell(firstMine(s.engine));
    expect(s.isOver, isFalse);
    expect(s.engine.shieldAvailable, isFalse);
    s.tapCell(secondMine(s.engine));
    expect(s.engine.status, GameStatus.lost);
    await settle();
    expect(s.result!.won, isFalse);
    expect(app.stats.lost, 1);
    expect(app.hasSavedGame, isFalse);
    s.dispose();
  });

  test('clearing every safe tile wins, awards a medal and records the planet', () async {
    final (s, app, _) = await make();
    s.startNew(cfg);
    for (var i = 0; i < s.engine.mines.length; i++) {
      if (s.engine.mines[i] == 0) s.tapCell(i);
    }
    expect(s.engine.status, GameStatus.won);
    await settle();
    expect(s.result!.won, isTrue);
    expect(s.result!.medal, isNot(Medal.none));
    expect(app.stats.completed, 1);
    expect(app.planets.length, 1);
    s.dispose();
  });

  test('flag mode flags on tap; secondary reveals; reveal mode is the reverse', () async {
    final (s, _, _) = await make();
    s.startNew(cfg);
    final safe = s.engine.mines.indexOf(0);
    s.setMode(InputMode.flag);
    s.tapCell(safe);
    expect(s.engine.state[safe], CellCode.flagged);
    s.secondaryCell(safe); // flagged cell cannot be revealed
    expect(s.engine.state[safe], CellCode.flagged);
    s.setMode(InputMode.reveal);
    s.secondaryCell(safe); // secondary in reveal mode = flag toggle
    expect(s.engine.state[safe], CellCode.hidden);
    s.dispose();
  });

  test('no input while paused', () async {
    final (s, _, _) = await make();
    s.startNew(cfg);
    s.pause();
    s.tapCell(s.engine.mines.indexOf(0));
    expect(s.engine.revealedSafe, 0);
    s.resume();
    s.tapCell(s.engine.mines.indexOf(0));
    expect(s.engine.revealedSafe, greaterThan(0));
    s.dispose();
  });

  test('autosave then resume restores flags, reveals, shield and timer', () async {
    final (s, app, store) = await make();
    s.startNew(cfg);
    s.tapCell(firstMine(s.engine)); // consumes shield
    final safe = s.engine.mines.indexOf(0);
    s.tapCell(safe);
    final target = s.engine.mines.lastIndexOf(1);
    s.setMode(InputMode.flag);
    s.tapCell(target);
    s.pause();
    await settle();
    expect(app.hasSavedGame, isTrue);
    final saved = Map<String, Object?>.from(app.savedGame!);

    // "Restart the app": fresh AppState from the same store.
    final app2 = await AppState.load(store);
    final s2 = GameSession(
      app: app2,
      globe: GlobeController(frequency: 3),
      audio: SilentAudio(),
      haptics: Haptics(enabled: false),
    );
    expect(s2.resumeSaved(), isTrue);
    expect(s2.engine.state, s.engine.state);
    expect(s2.engine.shieldAvailable, isFalse);
    expect(s2.engine.flagCount, 1);
    expect(s2.paused, isTrue);
    expect(s2.elapsedMs, saved['elapsedMs']);
    expect(s2.mode, InputMode.flag);
    s.dispose();
    s2.dispose();
  });

  test('restart gives a new planet for quick play, the same for campaign', () async {
    final (s, _, _) = await make();
    s.startNew(cfg.copyWith(seed: 99));
    s.restart();
    expect(s.config.seed, isNot(99));
    expect(s.config.frequency, 3);
    final campaign = GameConfig(
      frequency: 3,
      mineDensity: 0.1,
      seed: 5,
      environment: PlanetEnvironment.oceanic,
      mode: GameMode.campaign,
      missionId: 'x',
    );
    s.startNew(campaign);
    s.restart();
    expect(s.config.seed, 5);
    s.restart(sameSeed: true);
    expect(s.config.seed, 5);
    s.dispose();
  });
}
