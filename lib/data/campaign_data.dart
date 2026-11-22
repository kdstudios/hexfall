import '../core/game/game_config.dart';
import '../core/planet/planet_environment.dart';

/// Campaign content is plain data: add a row here and it appears in the game.
class Mission {
  const Mission({
    required this.id,
    required this.name,
    required this.briefing,
    required this.frequency,
    required this.density,
    required this.environment,
    required this.seed,
    this.anomaly = PlanetAnomaly.none,
  });

  final String id;
  final String name;
  final String briefing;
  final int frequency;
  final double density;
  final PlanetEnvironment environment;
  final int seed;
  final PlanetAnomaly anomaly;

  Difficulty get difficulty {
    if (frequency <= 5) return Difficulty.reconnaissance;
    if (frequency <= 9) return Difficulty.exploration;
    if (frequency <= 13) return Difficulty.deepSpace;
    return Difficulty.anomaly;
  }

  GameConfig toConfig() => GameConfig(
        frequency: frequency,
        mineDensity: density,
        seed: seed,
        environment: environment,
        anomaly: anomaly,
        difficulty: difficulty,
        mode: GameMode.campaign,
        missionId: id,
      );
}

class Sector {
  const Sector({
    required this.number,
    required this.name,
    required this.tagline,
    required this.missions,
    this.requiredFromPrevious = 3,
  });

  final int number;
  final String name;
  final String tagline;
  final List<Mission> missions;

  /// Missions that must be completed in the previous sector to unlock this one.
  final int requiredFromPrevious;

  String get title => 'Sector ${number.toString().padLeft(2, '0')} — $name';
}

const _o = PlanetEnvironment.oceanic;
const _d = PlanetEnvironment.desert;
const _f = PlanetEnvironment.frozen;
const _v = PlanetEnvironment.verdant;
const _l = PlanetEnvironment.volcanic;
const _c = PlanetEnvironment.crystalline;

class CampaignData {
  const CampaignData._();

  static const List<Sector> sectors = [
    Sector(
      number: 1,
      name: 'The Frontier',
      tagline: 'Safe-ish worlds on the edge of charted space.',
      missions: [
        Mission(id: 's1m1', name: 'First Light', briefing: 'Scan a tiny moon to calibrate the system.', frequency: 4, density: 0.07, environment: _o, seed: 31101),
        Mission(id: 's1m2', name: 'Green Harbour', briefing: 'A small verdant world with scattered mines.', frequency: 4, density: 0.08, environment: _v, seed: 31102),
        Mission(id: 's1m3', name: 'Dust Line', briefing: 'Dunes hide old defensive charges.', frequency: 5, density: 0.08, environment: _d, seed: 31103),
        Mission(id: 's1m4', name: 'Hollow Ice', briefing: 'Glacial crust, unstable readings.', frequency: 6, density: 0.09, environment: _f, seed: 31104),
        Mission(id: 's1m5', name: 'Gateway', briefing: 'The last frontier survey before deeper space.', frequency: 8, density: 0.10, environment: _o, seed: 31105),
      ],
    ),
    Sector(
      number: 2,
      name: 'The Forgotten',
      tagline: 'Abandoned colonies, armed and waiting.',
      missions: [
        Mission(id: 's2m1', name: 'Rust Orbit', briefing: 'An old mining world, heavily seeded.', frequency: 8, density: 0.10, environment: _d, seed: 32101),
        Mission(id: 's2m2', name: 'Ember Field', briefing: 'Molten seas and fissure vents.', frequency: 8, density: 0.11, environment: _l, seed: 32102, anomaly: PlanetAnomaly.seismicActivity),
        Mission(id: 's2m3', name: 'Silent Glacier', briefing: 'Ice hides the colony grid.', frequency: 9, density: 0.12, environment: _f, seed: 32103),
        Mission(id: 's2m4', name: 'Overgrowth', briefing: 'Jungle has swallowed the defences.', frequency: 10, density: 0.12, environment: _v, seed: 32104, anomaly: PlanetAnomaly.ionFog),
        Mission(id: 's2m5', name: 'Shard Choir', briefing: 'Resonating crystals mask sensor noise.', frequency: 10, density: 0.13, environment: _c, seed: 32105, anomaly: PlanetAnomaly.crystalResonance),
      ],
    ),
    Sector(
      number: 3,
      name: 'The Expanse',
      tagline: 'Vast worlds, dense minefields.',
      missions: [
        Mission(id: 's3m1', name: 'Blue Abyss', briefing: 'A global ocean with island chains.', frequency: 10, density: 0.13, environment: _o, seed: 33101),
        Mission(id: 's3m2', name: 'Cinder Reach', briefing: 'A volcanic giant under electromagnetic storms.', frequency: 11, density: 0.14, environment: _l, seed: 33102, anomaly: PlanetAnomaly.electromagneticStorm),
        Mission(id: 's3m3', name: 'Mirage', briefing: 'Endless dunes, shifting readings.', frequency: 12, density: 0.14, environment: _d, seed: 33103),
        Mission(id: 's3m4', name: 'Frostbite', briefing: 'A frozen giant with seismic activity.', frequency: 13, density: 0.15, environment: _f, seed: 33104, anomaly: PlanetAnomaly.seismicActivity),
        Mission(id: 's3m5', name: 'Canopy Crown', briefing: 'The largest verdant world yet charted.', frequency: 14, density: 0.15, environment: _v, seed: 33105, anomaly: PlanetAnomaly.ionFog),
      ],
    ),
    Sector(
      number: 4,
      name: 'The Unknown',
      tagline: 'No charts. No second chances.',
      missions: [
        Mission(id: 's4m1', name: 'Prism Wake', briefing: 'A crystal world humming with energy.', frequency: 14, density: 0.15, environment: _c, seed: 34101, anomaly: PlanetAnomaly.crystalResonance),
        Mission(id: 's4m2', name: 'Maw', briefing: 'A volcanic maelstrom. Bring the shield.', frequency: 15, density: 0.16, environment: _l, seed: 34102, anomaly: PlanetAnomaly.electromagneticStorm),
        Mission(id: 's4m3', name: 'Whisper', briefing: 'Fog hides everything but the numbers.', frequency: 16, density: 0.16, environment: _o, seed: 34103, anomaly: PlanetAnomaly.ionFog),
        Mission(id: 's4m4', name: 'Fault Line', briefing: 'The surface is breaking apart.', frequency: 16, density: 0.17, environment: _d, seed: 34104, anomaly: PlanetAnomaly.seismicActivity),
        Mission(id: 's4m5', name: 'HEXFALL', briefing: 'The final world. Clear it.', frequency: 18, density: 0.17, environment: _c, seed: 34105, anomaly: PlanetAnomaly.electromagneticStorm),
      ],
    ),
  ];

  static Mission? mission(String id) {
    for (final s in sectors) {
      for (final m in s.missions) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  static int totalMissions() => sectors.fold(0, (n, s) => n + s.missions.length);
}
