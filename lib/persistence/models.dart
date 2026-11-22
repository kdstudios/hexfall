import '../core/game/game_config.dart';
import '../core/game/medals.dart';
import '../core/planet/planet_environment.dart';

enum NumberPalette { standard, colorBlind, highContrast }

enum RenderQuality { low, medium, high, auto }

class Settings {
  const Settings({
    this.masterVolume = 0.8,
    this.musicVolume = 0.5,
    this.sfxVolume = 0.8,
    this.ambientVolume = 0.5,
    this.muted = false,
    this.haptics = true,
    this.palette = NumberPalette.standard,
    this.reducedMotion = false,
    this.uiScale = 1.0,
    this.leftHanded = false,
    this.longPressFlag = true,
    this.quality = RenderQuality.auto,
    this.anomalyEffects = true,
    this.scanEffects = true,
    this.hiddenTint = defaultHiddenTint,
    this.scannedTint = defaultScannedTint,
    this.depthWalls = true,
    this.depthEdges = true,
    this.depthRelief = true,
    this.animatedSky = true,
  });

  /// Strength of the terrain colour on hidden / scanned tiles (0 = plain metal).
  static const double defaultHiddenTint = 1.0;
  static const double defaultScannedTint = 0.6;

  final double masterVolume;
  final double musicVolume;
  final double sfxVolume;
  final double ambientVolume;
  final bool muted;
  final bool haptics;
  final NumberPalette palette;
  final bool reducedMotion;
  final double uiScale;
  final bool leftHanded;
  final bool longPressFlag;
  final RenderQuality quality;
  final bool anomalyEffects;
  final bool scanEffects;

  final double hiddenTint;
  final double scannedTint;

  /// Depth effects: raised tile sides near the limb, sun-facing edge glints,
  /// and the baked relief version of the plate art.
  final bool depthWalls;
  final bool depthEdges;
  final bool depthRelief;
  final bool animatedSky;

  Settings copyWith({
    double? masterVolume,
    double? musicVolume,
    double? sfxVolume,
    double? ambientVolume,
    bool? muted,
    bool? haptics,
    NumberPalette? palette,
    bool? reducedMotion,
    double? uiScale,
    bool? leftHanded,
    bool? longPressFlag,
    RenderQuality? quality,
    bool? anomalyEffects,
    bool? scanEffects,
    double? hiddenTint,
    double? scannedTint,
    bool? depthWalls,
    bool? depthEdges,
    bool? depthRelief,
    bool? animatedSky,
  }) =>
      Settings(
        masterVolume: masterVolume ?? this.masterVolume,
        musicVolume: musicVolume ?? this.musicVolume,
        sfxVolume: sfxVolume ?? this.sfxVolume,
        ambientVolume: ambientVolume ?? this.ambientVolume,
        muted: muted ?? this.muted,
        haptics: haptics ?? this.haptics,
        palette: palette ?? this.palette,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        uiScale: uiScale ?? this.uiScale,
        leftHanded: leftHanded ?? this.leftHanded,
        longPressFlag: longPressFlag ?? this.longPressFlag,
        quality: quality ?? this.quality,
        anomalyEffects: anomalyEffects ?? this.anomalyEffects,
        scanEffects: scanEffects ?? this.scanEffects,
        hiddenTint: hiddenTint ?? this.hiddenTint,
        scannedTint: scannedTint ?? this.scannedTint,
        depthWalls: depthWalls ?? this.depthWalls,
        depthEdges: depthEdges ?? this.depthEdges,
        depthRelief: depthRelief ?? this.depthRelief,
        animatedSky: animatedSky ?? this.animatedSky,
      );

  Map<String, Object?> toJson() => {
        'master': masterVolume,
        'music': musicVolume,
        'sfx': sfxVolume,
        'ambient': ambientVolume,
        'muted': muted,
        'haptics': haptics,
        'palette': palette.index,
        'reduced': reducedMotion,
        'scale': uiScale,
        'left': leftHanded,
        'longPress': longPressFlag,
        'quality': quality.index,
        'anomaly': anomalyEffects,
        'scan': scanEffects,
        'tintHidden': hiddenTint,
        'tintScanned': scannedTint,
        'dWalls': depthWalls,
        'dEdges': depthEdges,
        'dRelief': depthRelief,
        'sky': animatedSky,
      };

  factory Settings.fromJson(Map<String, Object?> j) {
    const d = Settings();
    double dbl(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    bool bol(String k, bool def) => j[k] as bool? ?? def;
    int idx(String k, int max, int def) {
      final v = j[k] as int?;
      return v != null && v >= 0 && v < max ? v : def;
    }

    return Settings(
      masterVolume: dbl('master', d.masterVolume),
      musicVolume: dbl('music', d.musicVolume),
      sfxVolume: dbl('sfx', d.sfxVolume),
      ambientVolume: dbl('ambient', d.ambientVolume),
      muted: bol('muted', d.muted),
      haptics: bol('haptics', d.haptics),
      palette: NumberPalette.values[idx('palette', NumberPalette.values.length, 0)],
      reducedMotion: bol('reduced', d.reducedMotion),
      uiScale: dbl('scale', d.uiScale).clamp(0.8, 1.4).toDouble(),
      leftHanded: bol('left', d.leftHanded),
      longPressFlag: bol('longPress', d.longPressFlag),
      quality: RenderQuality.values[idx('quality', RenderQuality.values.length, 3)],
      anomalyEffects: bol('anomaly', d.anomalyEffects),
      scanEffects: bol('scan', d.scanEffects),
      hiddenTint: dbl('tintHidden', d.hiddenTint).clamp(0.0, 1.2).toDouble(),
      scannedTint: dbl('tintScanned', d.scannedTint).clamp(0.0, 1.2).toDouble(),
      depthWalls: bol('dWalls', d.depthWalls),
      depthEdges: bol('dEdges', d.depthEdges),
      depthRelief: bol('dRelief', d.depthRelief),
      animatedSky: bol('sky', d.animatedSky),
    );
  }
}

class PlayerStats {
  PlayerStats({
    this.gamesPlayed = 0,
    this.completed = 0,
    this.lost = 0,
    this.minesDiscovered = 0,
    this.shieldsUsed = 0,
    this.totalTimeMs = 0,
    Map<String, int>? bestTimesMs,
    Map<String, int>? bestMedal,
    List<int>? medalCounts,
  })  : bestTimesMs = bestTimesMs ?? {},
        bestMedal = bestMedal ?? {},
        medalCounts = medalCounts ?? [0, 0, 0];

  int gamesPlayed;
  int completed;
  int lost;
  int minesDiscovered;
  int shieldsUsed;
  int totalTimeMs;

  /// Keyed by difficulty name.
  final Map<String, int> bestTimesMs;
  final Map<String, int> bestMedal;

  /// [bronze, silver, gold]
  final List<int> medalCounts;

  Map<String, Object?> toJson() => {
        'played': gamesPlayed,
        'completed': completed,
        'lost': lost,
        'mines': minesDiscovered,
        'shields': shieldsUsed,
        'time': totalTimeMs,
        'best': bestTimesMs,
        'bestMedal': bestMedal,
        'medals': medalCounts,
      };

  factory PlayerStats.fromJson(Map<String, Object?> j) => PlayerStats(
        gamesPlayed: j['played'] as int? ?? 0,
        completed: j['completed'] as int? ?? 0,
        lost: j['lost'] as int? ?? 0,
        minesDiscovered: j['mines'] as int? ?? 0,
        shieldsUsed: j['shields'] as int? ?? 0,
        totalTimeMs: j['time'] as int? ?? 0,
        bestTimesMs: ((j['best'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as int)),
        bestMedal: ((j['bestMedal'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as int)),
        medalCounts: ((j['medals'] as List?) ?? [0, 0, 0]).map((e) => e as int).toList(),
      );
}

class MissionRecord {
  const MissionRecord({required this.medal, required this.bestMs});
  final Medal medal;
  final int bestMs;

  Map<String, Object?> toJson() => {'m': medal.index, 't': bestMs};
  factory MissionRecord.fromJson(Map<String, Object?> j) =>
      MissionRecord(medal: Medal.values[j['m'] as int], bestMs: j['t'] as int);
}

class DailyRecord {
  const DailyRecord({required this.completed, required this.attempts, this.bestMs = 0, this.medal = Medal.none});
  final bool completed;
  final int attempts;
  final int bestMs;
  final Medal medal;

  Map<String, Object?> toJson() => {'c': completed, 'a': attempts, 't': bestMs, 'm': medal.index};
  factory DailyRecord.fromJson(Map<String, Object?> j) => DailyRecord(
        completed: j['c'] as bool,
        attempts: j['a'] as int,
        bestMs: j['t'] as int? ?? 0,
        medal: Medal.values[j['m'] as int? ?? 0],
      );
}

class PlanetEntry {
  PlanetEntry({
    required this.id,
    required this.name,
    required this.environment,
    required this.seed,
    required this.frequency,
    required this.density,
    required this.difficulty,
    required this.anomaly,
    required this.discovered,
    this.completed = false,
    this.bestMs = 0,
    this.medal = Medal.none,
  });

  final String id;
  final String name;
  final PlanetEnvironment environment;
  final int seed;
  final int frequency;
  final double density;
  final Difficulty difficulty;
  final PlanetAnomaly anomaly;
  final DateTime discovered;
  bool completed;
  int bestMs;
  Medal medal;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'env': environment.index,
        'seed': seed,
        'f': frequency,
        'd': density,
        'df': difficulty.index,
        'an': anomaly.index,
        'date': discovered.toIso8601String(),
        'done': completed,
        'best': bestMs,
        'medal': medal.index,
      };

  factory PlanetEntry.fromJson(Map<String, Object?> j) => PlanetEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        environment: PlanetEnvironment.values[j['env'] as int],
        seed: j['seed'] as int,
        frequency: j['f'] as int,
        density: (j['d'] as num).toDouble(),
        difficulty: Difficulty.values[j['df'] as int],
        anomaly: PlanetAnomaly.values[j['an'] as int],
        discovered: DateTime.parse(j['date'] as String),
        completed: j['done'] as bool,
        bestMs: j['best'] as int,
        medal: Medal.values[j['medal'] as int],
      );
}
