import 'dart:ui' show Color;

import '../game/seeded_random.dart';

enum PlanetEnvironment { oceanic, desert, frozen, verdant, volcanic, crystalline }

extension PlanetEnvironmentInfo on PlanetEnvironment {
  String get label => switch (this) {
        PlanetEnvironment.oceanic => 'Oceanic',
        PlanetEnvironment.desert => 'Desert',
        PlanetEnvironment.frozen => 'Frozen',
        PlanetEnvironment.verdant => 'Verdant',
        PlanetEnvironment.volcanic => 'Volcanic',
        PlanetEnvironment.crystalline => 'Crystalline',
      };

  String get blurb => switch (this) {
        PlanetEnvironment.oceanic => 'Deep blue oceans, cloud formations and luminous coastlines.',
        PlanetEnvironment.desert => 'Rust-coloured terrain, giant dunes and dusty atmosphere.',
        PlanetEnvironment.frozen => 'Glacial terrain, icy cracks and frozen oceans.',
        PlanetEnvironment.verdant => 'Green continents, dense vegetation and atmospheric haze.',
        PlanetEnvironment.volcanic => 'Molten seas, black basalt and glowing fissures.',
        PlanetEnvironment.crystalline => 'Violet and teal crystal fields under an aurora sky.',
      };
}

/// Cosmetic-only anomalies. They never touch mine placement or numbers.
enum PlanetAnomaly { none, electromagneticStorm, ionFog, seismicActivity, crystalResonance }

extension PlanetAnomalyInfo on PlanetAnomaly {
  String get label => switch (this) {
        PlanetAnomaly.none => 'None',
        PlanetAnomaly.electromagneticStorm => 'Electromagnetic Storm',
        PlanetAnomaly.ionFog => 'Ion Fog',
        PlanetAnomaly.seismicActivity => 'Seismic Activity',
        PlanetAnomaly.crystalResonance => 'Crystal Resonance',
      };

  /// Haze / accent colour used by the renderer (rgb 0..255).
  Color get tint => switch (this) {
        PlanetAnomaly.none => const Color(0x00000000),
        PlanetAnomaly.electromagneticStorm => const Color(0xFF9AA8FF),
        PlanetAnomaly.ionFog => const Color(0xFF5CFFC8),
        PlanetAnomaly.seismicActivity => const Color(0xFFFF8A3C),
        PlanetAnomaly.crystalResonance => const Color(0xFFD08CFF),
      };
}

/// Colour recipe for one planet. All colours are rgb 0..1.
class PlanetStyle {
  const PlanetStyle({
    required this.seaLevel,
    required this.deepSea,
    required this.shallowSea,
    required this.landLow,
    required this.landMid,
    required this.landHigh,
    required this.ice,
    required this.iceStart,
    required this.noiseFreq,
    required this.atmosphere,
  });

  final double seaLevel;
  final List<double> deepSea;
  final List<double> shallowSea;
  final List<double> landLow;
  final List<double> landMid;
  final List<double> landHigh;
  final List<double> ice;
  final double iceStart; // |y| above which ice appears
  final double noiseFreq;
  final Color atmosphere;
}

const Map<PlanetEnvironment, PlanetStyle> _baseStyles = {
  PlanetEnvironment.oceanic: PlanetStyle(
    seaLevel: 0.62,
    deepSea: [0.02, 0.10, 0.28],
    shallowSea: [0.08, 0.48, 0.68],
    landLow: [0.78, 0.74, 0.55],
    landMid: [0.20, 0.55, 0.32],
    landHigh: [0.55, 0.52, 0.45],
    ice: [0.90, 0.96, 1.0],
    iceStart: 0.85,
    noiseFreq: 2.2,
    atmosphere: Color(0xFF39B8FF),
  ),
  PlanetEnvironment.desert: PlanetStyle(
    seaLevel: 0.28,
    deepSea: [0.22, 0.10, 0.06],
    shallowSea: [0.45, 0.22, 0.10],
    landLow: [0.88, 0.62, 0.33],
    landMid: [0.80, 0.40, 0.18],
    landHigh: [0.55, 0.25, 0.12],
    ice: [0.95, 0.85, 0.70],
    iceStart: 2.0,
    noiseFreq: 2.8,
    atmosphere: Color(0xFFFF9A55),
  ),
  PlanetEnvironment.frozen: PlanetStyle(
    seaLevel: 0.45,
    deepSea: [0.05, 0.20, 0.32],
    shallowSea: [0.25, 0.62, 0.75],
    landLow: [0.82, 0.90, 0.95],
    landMid: [0.62, 0.75, 0.85],
    landHigh: [0.95, 0.98, 1.0],
    ice: [0.95, 0.98, 1.0],
    iceStart: 0.55,
    noiseFreq: 2.4,
    atmosphere: Color(0xFF9FE6FF),
  ),
  PlanetEnvironment.verdant: PlanetStyle(
    seaLevel: 0.40,
    deepSea: [0.02, 0.20, 0.28],
    shallowSea: [0.10, 0.55, 0.58],
    landLow: [0.45, 0.72, 0.35],
    landMid: [0.12, 0.45, 0.20],
    landHigh: [0.25, 0.32, 0.18],
    ice: [0.90, 0.96, 1.0],
    iceStart: 0.92,
    noiseFreq: 2.2,
    atmosphere: Color(0xFF6BFFB0),
  ),
  PlanetEnvironment.volcanic: PlanetStyle(
    seaLevel: 0.36,
    deepSea: [0.55, 0.10, 0.02],
    shallowSea: [1.0, 0.45, 0.08],
    landLow: [0.16, 0.12, 0.11],
    landMid: [0.10, 0.08, 0.08],
    landHigh: [0.28, 0.20, 0.18],
    ice: [0.30, 0.30, 0.30],
    iceStart: 2.0,
    noiseFreq: 3.0,
    atmosphere: Color(0xFFFF6A33),
  ),
  PlanetEnvironment.crystalline: PlanetStyle(
    seaLevel: 0.40,
    deepSea: [0.15, 0.05, 0.35],
    shallowSea: [0.10, 0.60, 0.70],
    landLow: [0.45, 0.25, 0.75],
    landMid: [0.20, 0.65, 0.70],
    landHigh: [0.85, 0.55, 0.95],
    ice: [0.80, 0.90, 1.0],
    iceStart: 0.93,
    noiseFreq: 3.2,
    atmosphere: Color(0xFFB46BFF),
  ),
};

/// A concrete planet: environment preset + seed-driven variation + name.
class PlanetAppearance {
  PlanetAppearance._(this.environment, this.seed, this.style, this.name);

  final PlanetEnvironment environment;
  final int seed;
  final PlanetStyle style;
  final String name;

  factory PlanetAppearance.generate(PlanetEnvironment env, int seed) {
    final base = _baseStyles[env]!;
    final rnd = SeededRandom(seed ^ 0x51ED270B);
    List<double> jitter(List<double> c, double amount) => [
          for (final v in c) (v + (rnd.nextDouble() - 0.5) * amount).clamp(0.0, 1.0).toDouble(),
        ];
    final style = PlanetStyle(
      seaLevel: (base.seaLevel + (rnd.nextDouble() - 0.5) * 0.12).clamp(0.05, 0.85).toDouble(),
      deepSea: jitter(base.deepSea, 0.10),
      shallowSea: jitter(base.shallowSea, 0.10),
      landLow: jitter(base.landLow, 0.12),
      landMid: jitter(base.landMid, 0.12),
      landHigh: jitter(base.landHigh, 0.12),
      ice: base.ice,
      iceStart: base.iceStart,
      noiseFreq: base.noiseFreq * (0.85 + 0.3 * rnd.nextDouble()),
      atmosphere: base.atmosphere,
    );
    return PlanetAppearance._(env, seed, style, PlanetNamer.name(seed));
  }
}

/// Deterministic planet names from a seed, e.g. "Velorias-27".
class PlanetNamer {
  const PlanetNamer._();

  static const _starts = [
    'Ka', 'Ve', 'Zor', 'Xan', 'Ori', 'Lum', 'Tyr', 'Nex', 'Cael', 'Mor',
    'Sol', 'Eth', 'Ry', 'Hel', 'Quo', 'Ul', 'Bra', 'Dra', 'Fen', 'Gal',
  ];
  static const _mids = ['ra', 'lo', 'vi', 'na', 'te', 'xu', 'mi', 'dor', 'sa', 'ke'];
  static const _ends = ['on', 'is', 'ar', 'ex', 'um', 'ia', 'os', 'eth', 'ix', 'ia'];

  static String name(int seed) {
    final rnd = SeededRandom(seed ^ 0x2545F491);
    final a = _starts[rnd.nextInt(_starts.length)];
    final b = _mids[rnd.nextInt(_mids.length)];
    final c = _ends[rnd.nextInt(_ends.length)];
    final n = 1 + rnd.nextInt(99);
    return '$a$b$c-$n';
  }
}
