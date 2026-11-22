import 'game_config.dart';

enum Medal { none, bronze, silver, gold }

extension MedalInfo on Medal {
  String get label => switch (this) {
        Medal.none => 'No medal',
        Medal.bronze => 'Bronze Explorer',
        Medal.silver => 'Silver Explorer',
        Medal.gold => 'Gold Explorer',
      };
}

/// Transparent medal rules. Shown to the player on the results screen.
class MedalRules {
  const MedalRules._();

  /// Gold time target: this many seconds per cell (configurable).
  static const double goldSecondsPerCell = 0.5;

  static int goldTimeTargetMs(GameConfig c) => (c.cellCount * goldSecondsPerCell * 1000).round();

  static const String bronzeText = 'Bronze: complete the planet.';
  static const String silverText = 'Silver: complete without using the shield.';
  static String goldText(GameConfig c) =>
      'Gold: no shield, no incorrect flags, under ${(goldTimeTargetMs(c) / 1000).round()} s.';

  static Medal evaluate({
    required bool won,
    required bool shieldUsed,
    required int incorrectFlags,
    required int elapsedMs,
    required GameConfig config,
  }) {
    if (!won) return Medal.none;
    if (shieldUsed) return Medal.bronze;
    if (incorrectFlags == 0 && elapsedMs <= goldTimeTargetMs(config)) return Medal.gold;
    return Medal.silver;
  }
}
