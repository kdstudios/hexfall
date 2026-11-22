import 'package:flutter/material.dart';

import '../../core/game/medals.dart';

Color medalColor(Medal m) => switch (m) {
      Medal.none => const Color(0xFF4A6070),
      Medal.bronze => const Color(0xFFCD7F32),
      Medal.silver => const Color(0xFFC8D4DC),
      Medal.gold => const Color(0xFFFFD34D),
    };

class MedalBadge extends StatelessWidget {
  const MedalBadge({super.key, required this.medal, this.size = 22});

  final Medal medal;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: medal.label,
        child: Icon(Icons.military_tech, size: size, color: medalColor(medal)),
      );
}
