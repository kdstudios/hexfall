import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/game/game_config.dart';
import '../core/game/medals.dart';
import '../data/campaign_data.dart';
import 'key_value_store.dart';
import 'models.dart';

/// Summary of a finished game, produced by the game session.
class FinishedGame {
  const FinishedGame({
    required this.config,
    required this.planetName,
    required this.won,
    required this.elapsedMs,
    required this.percentCleared,
    required this.shieldUsed,
    required this.incorrectFlags,
    required this.minesDiscovered,
    required this.medal,
  });

  final GameConfig config;
  final String planetName;
  final bool won;
  final int elapsedMs;
  final double percentCleared;
  final bool shieldUsed;
  final int incorrectFlags;
  final int minesDiscovered;
  final Medal medal;
}

class RecordOutcome {
  const RecordOutcome({required this.newBestTime, required this.newBestMedal});
  final bool newBestTime;
  final bool newBestMedal;
}

/// All persistent player data. Every change is written to the store
/// immediately (one key per data set, each write replaces its whole value, so
/// a crash can never leave a half-written file).
class AppState extends ChangeNotifier {
  AppState(this._store);

  final KeyValueStore _store;

  static const _kSettings = 'hexfall.settings.v1';
  static const _kStats = 'hexfall.stats.v1';
  static const _kCampaign = 'hexfall.campaign.v1';
  static const _kDaily = 'hexfall.daily.v1';
  static const _kPlanets = 'hexfall.planets.v1';
  static const _kGame = 'hexfall.savegame.v1';

  Settings settings = const Settings();
  PlayerStats stats = PlayerStats();
  final Map<String, MissionRecord> campaign = {};
  final Map<String, DailyRecord> daily = {};
  final Map<String, PlanetEntry> planets = {};

  /// Unfinished game snapshot (engine json + elapsed + meta), if any.
  Map<String, Object?>? savedGame;

  static Future<AppState> load(KeyValueStore store) async {
    final s = AppState(store);
    await s._loadAll();
    return s;
  }

  Future<Map<String, Object?>?> _readJson(String key) async {
    try {
      final raw = await _store.read(key);
      if (raw == null) return null;
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      return null; // corrupt data is ignored rather than crashing start-up
    }
  }

  Future<void> _loadAll() async {
    final st = await _readJson(_kSettings);
    if (st != null) settings = Settings.fromJson(st);
    final ps = await _readJson(_kStats);
    if (ps != null) stats = PlayerStats.fromJson(ps);
    final cp = await _readJson(_kCampaign);
    cp?.forEach((k, v) {
      try {
        campaign[k] = MissionRecord.fromJson((v as Map).cast<String, Object?>());
      } catch (_) {}
    });
    final dl = await _readJson(_kDaily);
    dl?.forEach((k, v) {
      try {
        daily[k] = DailyRecord.fromJson((v as Map).cast<String, Object?>());
      } catch (_) {}
    });
    final pl = await _readJson(_kPlanets);
    pl?.forEach((k, v) {
      try {
        planets[k] = PlanetEntry.fromJson((v as Map).cast<String, Object?>());
      } catch (_) {}
    });
    savedGame = await _readJson(_kGame);
  }

  Future<void> _write(String key, Object? json) => _store.write(key, jsonEncode(json));

  // --- Settings ----------------------------------------------------------------

  Future<void> updateSettings(Settings s) async {
    settings = s;
    notifyListeners();
    await _write(_kSettings, s.toJson());
  }

  // --- Save game ---------------------------------------------------------------

  Future<void> saveGame(Map<String, Object?> snapshot) async {
    savedGame = snapshot;
    await _write(_kGame, snapshot);
    notifyListeners();
  }

  Future<void> clearSavedGame() async {
    savedGame = null;
    await _store.remove(_kGame);
    notifyListeners();
  }

  bool get hasSavedGame => savedGame != null;

  // --- Results -------------------------------------------------------------------

  static String planetId(GameConfig c) =>
      '${c.seed}-${c.frequency}-${(c.mineDensity * 1000).round()}-${c.environment.index}-${c.anomaly.index}';

  Future<RecordOutcome> recordFinished(FinishedGame g, {required DateTime now}) async {
    final key = g.config.difficulty.name;
    stats.gamesPlayed++;
    stats.totalTimeMs += g.elapsedMs;
    stats.minesDiscovered += g.minesDiscovered;
    if (g.shieldUsed) stats.shieldsUsed++;

    var newBestTime = false;
    var newBestMedal = false;
    if (g.won) {
      stats.completed++;
      if (g.medal.index > 0) stats.medalCounts[g.medal.index - 1]++;
      final best = stats.bestTimesMs[key];
      if (best == null || g.elapsedMs < best) {
        stats.bestTimesMs[key] = g.elapsedMs;
        newBestTime = true;
      }
      final bestMedal = stats.bestMedal[key] ?? 0;
      if (g.medal.index > bestMedal) {
        stats.bestMedal[key] = g.medal.index;
        newBestMedal = true;
      }
    } else {
      stats.lost++;
    }

    // Planet database.
    final id = planetId(g.config);
    final entry = planets.putIfAbsent(
      id,
      () => PlanetEntry(
        id: id,
        name: g.planetName,
        environment: g.config.environment,
        seed: g.config.seed,
        frequency: g.config.frequency,
        density: g.config.mineDensity,
        difficulty: g.config.difficulty,
        anomaly: g.config.anomaly,
        discovered: now,
      ),
    );
    if (g.won) {
      if (!entry.completed || g.elapsedMs < entry.bestMs) entry.bestMs = g.elapsedMs;
      entry.completed = true;
      if (g.medal.index > entry.medal.index) entry.medal = g.medal;
    }

    // Campaign.
    final mid = g.config.missionId;
    if (g.won && mid != null) {
      final old = campaign[mid];
      campaign[mid] = MissionRecord(
        medal: old == null || g.medal.index > old.medal.index ? g.medal : old.medal,
        bestMs: old == null || g.elapsedMs < old.bestMs ? g.elapsedMs : old.bestMs,
      );
    }

    // Daily.
    final dkey = g.config.dailyDate;
    if (dkey != null) {
      final old = daily[dkey];
      final bestMs = g.won ? (old != null && old.completed && old.bestMs < g.elapsedMs ? old.bestMs : g.elapsedMs) : (old?.bestMs ?? 0);
      final medal = g.won ? (old != null && old.medal.index > g.medal.index ? old.medal : g.medal) : (old?.medal ?? Medal.none);
      daily[dkey] = DailyRecord(
        completed: g.won || (old?.completed ?? false),
        attempts: (old?.attempts ?? 0) + 1,
        bestMs: bestMs,
        medal: medal,
      );
    }

    await Future.wait([
      _write(_kStats, stats.toJson()),
      _write(_kPlanets, planets.map((k, v) => MapEntry(k, v.toJson()))),
      _write(_kCampaign, campaign.map((k, v) => MapEntry(k, v.toJson()))),
      _write(_kDaily, daily.map((k, v) => MapEntry(k, v.toJson()))),
    ]);
    await clearSavedGame();
    return RecordOutcome(newBestTime: newBestTime, newBestMedal: newBestMedal);
  }

  // --- Campaign queries ------------------------------------------------------------

  int completedInSector(int sectorIndex) {
    var n = 0;
    for (final m in CampaignData.sectors[sectorIndex].missions) {
      if (campaign.containsKey(m.id)) n++;
    }
    return n;
  }

  bool isSectorUnlocked(int sectorIndex) {
    if (sectorIndex == 0) return true;
    final need = CampaignData.sectors[sectorIndex].requiredFromPrevious;
    return completedInSector(sectorIndex - 1) >= need;
  }

  bool isMissionUnlocked(int sectorIndex, int missionIndex) {
    if (!isSectorUnlocked(sectorIndex)) return false;
    if (missionIndex == 0) return true;
    final prev = CampaignData.sectors[sectorIndex].missions[missionIndex - 1];
    return campaign.containsKey(prev.id);
  }
}
