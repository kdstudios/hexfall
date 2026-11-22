import '../geometry/geodesic_grid.dart';
import '../planet/planet_environment.dart';

enum Difficulty { reconnaissance, exploration, deepSpace, anomaly, custom }

extension DifficultyInfo on Difficulty {
  String get label => switch (this) {
        Difficulty.reconnaissance => 'Reconnaissance',
        Difficulty.exploration => 'Exploration',
        Difficulty.deepSpace => 'Deep Space',
        Difficulty.anomaly => 'Anomaly',
        Difficulty.custom => 'Custom',
      };

  int get frequency => switch (this) {
        Difficulty.reconnaissance => 4,
        Difficulty.exploration => 8,
        Difficulty.deepSpace => 10,
        Difficulty.anomaly => 16,
        Difficulty.custom => 8,
      };

  double get density => switch (this) {
        Difficulty.reconnaissance => 0.08,
        Difficulty.exploration => 0.10,
        Difficulty.deepSpace => 0.13,
        Difficulty.anomaly => 0.16,
        Difficulty.custom => 0.12,
      };

  String get blurb => switch (this) {
        Difficulty.reconnaissance => 'A small, forgiving world. Learn the geometry.',
        Difficulty.exploration => 'A standard survey. The classic challenge.',
        Difficulty.deepSpace => 'A large planet with a dense minefield.',
        Difficulty.anomaly => 'A vast, hostile world. Expect to need the shield.',
        Difficulty.custom => 'Choose your own size and density.',
      };
}

enum GameMode { quick, campaign, daily }

/// Everything needed to rebuild a planet and its minefield exactly.
class GameConfig {
  const GameConfig({
    required this.frequency,
    required this.mineDensity,
    required this.seed,
    required this.environment,
    this.anomaly = PlanetAnomaly.none,
    this.difficulty = Difficulty.exploration,
    this.mode = GameMode.quick,
    this.missionId,
    this.dailyDate,
  });

  /// Custom-game limits (kept modest so phones stay smooth).
  static const int customMinFrequency = 3;
  static const int customMaxFrequency = 20;
  static const double customMinDensity = 0.04;
  static const double customMaxDensity = 0.30;

  final int frequency;
  final double mineDensity;
  final int seed;
  final PlanetEnvironment environment;
  final PlanetAnomaly anomaly;
  final Difficulty difficulty;
  final GameMode mode;
  final String? missionId;
  final String? dailyDate;

  int get cellCount => GeodesicGrid.cellCountFor(frequency);

  int get mineCount {
    final m = (cellCount * mineDensity).round();
    return m.clamp(1, cellCount - 13).toInt();
  }

  /// Null if valid, otherwise a human readable problem.
  static String? validateCustom(int frequency, double density) {
    if (frequency < customMinFrequency || frequency > customMaxFrequency) {
      return 'Frequency must be $customMinFrequency–$customMaxFrequency.';
    }
    if (density < customMinDensity || density > customMaxDensity) {
      return 'Mine density must be ${(customMinDensity * 100).round()}–${(customMaxDensity * 100).round()}%.';
    }
    return null;
  }

  GameConfig copyWith({int? seed, PlanetEnvironment? environment}) => GameConfig(
        frequency: frequency,
        mineDensity: mineDensity,
        seed: seed ?? this.seed,
        environment: environment ?? this.environment,
        anomaly: anomaly,
        difficulty: difficulty,
        mode: mode,
        missionId: missionId,
        dailyDate: dailyDate,
      );

  Map<String, Object?> toJson() => {
        'f': frequency,
        'd': mineDensity,
        's': seed,
        'e': environment.index,
        'a': anomaly.index,
        'df': difficulty.index,
        'm': mode.index,
        'mi': missionId,
        'dd': dailyDate,
      };

  factory GameConfig.fromJson(Map<String, Object?> j) => GameConfig(
        frequency: j['f'] as int,
        mineDensity: (j['d'] as num).toDouble(),
        seed: j['s'] as int,
        environment: PlanetEnvironment.values[j['e'] as int],
        anomaly: PlanetAnomaly.values[j['a'] as int],
        difficulty: Difficulty.values[j['df'] as int],
        mode: GameMode.values[j['m'] as int],
        missionId: j['mi'] as String?,
        dailyDate: j['dd'] as String?,
      );
}
