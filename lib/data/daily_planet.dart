import '../core/game/game_config.dart';
import '../core/game/seeded_random.dart';
import '../core/planet/planet_environment.dart';

/// One shared planet per UTC day, derived purely from the date. Works offline.
class DailyPlanet {
  const DailyPlanet._();

  /// Bump if the generation algorithm ever changes; old dates then differ
  /// deliberately instead of silently changing.
  static const int generationVersion = 1;

  static String dateKey(DateTime utc) {
    final d = utc.toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static int seedFor(String key) =>
      SeededRandom.hashString('hexfall-daily-v$generationVersion-$key');

  static GameConfig forDate(DateTime utc) {
    final key = dateKey(utc);
    final seed = seedFor(key);
    final rnd = SeededRandom(seed);
    final env = PlanetEnvironment.values[rnd.nextInt(PlanetEnvironment.values.length)];
    final anomaly = PlanetAnomaly.values[rnd.nextInt(PlanetAnomaly.values.length)];
    return GameConfig(
      frequency: 10,
      mineDensity: 0.13,
      seed: seed,
      environment: env,
      anomaly: anomaly,
      difficulty: Difficulty.deepSpace,
      mode: GameMode.daily,
      dailyDate: key,
    );
  }
}
