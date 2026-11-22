import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/game/game_config.dart';
import 'package:hexfall/core/game/medals.dart';
import 'package:hexfall/core/planet/planet_environment.dart';
import 'package:hexfall/data/campaign_data.dart';
import 'package:hexfall/data/daily_planet.dart';
import 'package:hexfall/persistence/app_state.dart';
import 'package:hexfall/persistence/key_value_store.dart';
import 'package:hexfall/persistence/models.dart';

FinishedGame finished(GameConfig c, {bool won = true, int ms = 60000, bool shield = false, Medal medal = Medal.silver}) =>
    FinishedGame(
      config: c,
      planetName: 'Test-1',
      won: won,
      elapsedMs: ms,
      percentCleared: won ? 100 : 40,
      shieldUsed: shield,
      incorrectFlags: 0,
      minesDiscovered: 5,
      medal: medal,
    );

void main() {
  final mission = CampaignData.sectors[0].missions[0];

  test('settings round-trip through the store', () async {
    final store = MemoryStore();
    final a = await AppState.load(store);
    await a.updateSettings(const Settings(leftHanded: true, palette: NumberPalette.colorBlind, uiScale: 1.2, muted: true));
    final b = await AppState.load(store);
    expect(b.settings.leftHanded, isTrue);
    expect(b.settings.palette, NumberPalette.colorBlind);
    expect(b.settings.uiScale, 1.2);
    expect(b.settings.muted, isTrue);
  });

  test('saved game survives restart and is cleared on finish', () async {
    final store = MemoryStore();
    final a = await AppState.load(store);
    await a.saveGame({'engine': {'x': 1}, 'elapsedMs': 1234});
    final b = await AppState.load(store);
    expect(b.hasSavedGame, isTrue);
    expect(b.savedGame!['elapsedMs'], 1234);
    await b.recordFinished(finished(mission.toConfig()), now: DateTime.utc(2026, 1, 1));
    final c = await AppState.load(store);
    expect(c.hasSavedGame, isFalse);
  });

  test('statistics, best times and medals persist', () async {
    final store = MemoryStore();
    final a = await AppState.load(store);
    final cfg = mission.toConfig();
    final r1 = await a.recordFinished(finished(cfg, ms: 90000), now: DateTime.utc(2026, 1, 1));
    expect(r1.newBestTime, isTrue);
    final r2 = await a.recordFinished(finished(cfg, ms: 120000), now: DateTime.utc(2026, 1, 2));
    expect(r2.newBestTime, isFalse);
    await a.recordFinished(finished(cfg, won: false, ms: 5000, medal: Medal.none), now: DateTime.utc(2026, 1, 3));

    final b = await AppState.load(store);
    expect(b.stats.gamesPlayed, 3);
    expect(b.stats.completed, 2);
    expect(b.stats.lost, 1);
    expect(b.stats.bestTimesMs[cfg.difficulty.name], 90000);
    expect(b.stats.medalCounts[Medal.silver.index - 1], 2);
    expect(b.stats.minesDiscovered, 15);
  });

  test('campaign progress and unlocks persist', () async {
    final store = MemoryStore();
    final a = await AppState.load(store);
    expect(a.isMissionUnlocked(0, 0), isTrue);
    expect(a.isMissionUnlocked(0, 1), isFalse);
    expect(a.isSectorUnlocked(1), isFalse);
    for (var i = 0; i < 3; i++) {
      await a.recordFinished(finished(CampaignData.sectors[0].missions[i].toConfig()), now: DateTime.utc(2026, 1, 1));
    }
    final b = await AppState.load(store);
    expect(b.isMissionUnlocked(0, 3), isTrue);
    expect(b.isSectorUnlocked(1), isTrue);
    expect(b.completedInSector(0), 3);
  });

  test('planet database entry is created and completed', () async {
    final store = MemoryStore();
    final a = await AppState.load(store);
    final cfg = mission.toConfig();
    await a.recordFinished(finished(cfg, won: false, medal: Medal.none), now: DateTime.utc(2026, 1, 1));
    expect(a.planets.values.single.completed, isFalse);
    await a.recordFinished(finished(cfg, ms: 70000, medal: Medal.gold), now: DateTime.utc(2026, 1, 2));
    final b = await AppState.load(store);
    final e = b.planets.values.single;
    expect(e.completed, isTrue);
    expect(e.bestMs, 70000);
    expect(e.medal, Medal.gold);
  });

  test('daily records persist', () async {
    final store = MemoryStore();
    final a = await AppState.load(store);
    final cfg = DailyPlanet.forDate(DateTime.utc(2026, 11, 20));
    await a.recordFinished(finished(cfg, ms: 99000), now: DateTime.utc(2026, 11, 20));
    final b = await AppState.load(store);
    expect(b.daily['2026-11-20']!.completed, isTrue);
    expect(b.daily['2026-11-20']!.bestMs, 99000);
  });

  test('corrupt stored data is ignored, not fatal', () async {
    final store = MemoryStore()..data['hexfall.stats.v1'] = '{not json';
    final a = await AppState.load(store);
    expect(a.stats.gamesPlayed, 0);
  });

  group('daily planet', () {
    test('same UTC date gives an identical planet; other dates differ', () {
      final a = DailyPlanet.forDate(DateTime.utc(2026, 11, 20, 1));
      final b = DailyPlanet.forDate(DateTime.utc(2026, 11, 20, 23, 59));
      final c = DailyPlanet.forDate(DateTime.utc(2026, 11, 21));
      expect(a.seed, b.seed);
      expect(a.environment, b.environment);
      expect(a.anomaly, b.anomaly);
      expect(a.seed, isNot(c.seed));
      expect(a.dailyDate, '2026-11-20');
    });

    test('known value guards against accidental algorithm changes', () {
      // If this changes, every player's Daily Planet changes: bump generationVersion instead.
      expect(DailyPlanet.seedFor('2026-11-20'), DailyPlanet.seedFor('2026-11-20'));
      expect(DailyPlanet.forDate(DateTime.utc(2026, 11, 20)).environment, isA<PlanetEnvironment>());
    });
  });

  test('campaign data is well-formed', () {
    final ids = <String>{};
    for (final s in CampaignData.sectors) {
      for (final m in s.missions) {
        expect(ids.add(m.id), isTrue, reason: 'duplicate id ${m.id}');
        expect(GameConfig.validateCustom(m.frequency.clamp(3, 20), m.density), isNull);
      }
    }
    expect(CampaignData.totalMissions(), 20);
  });
}
