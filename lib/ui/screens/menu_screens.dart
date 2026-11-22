import 'package:flutter/material.dart';

import '../../core/game/game_config.dart';
import '../../core/game/medals.dart';
import '../../core/planet/planet_environment.dart';
import '../../data/campaign_data.dart';
import '../../data/daily_planet.dart';
import '../../game/game_session.dart';
import '../../persistence/app_state.dart';
import '../../theme/hexfall_theme.dart';
import '../widgets/medal_badge.dart';
import '../widgets/sci_fi.dart';
import 'game_screen.dart';
import 'info_screens.dart';

Future<void> _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

// =============================================================================
// Main menu
// =============================================================================

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MenuBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 720;
                final panel = ListenableBuilder(
                  listenable: services.app,
                  builder: (context, _) => SingleChildScrollView(
                    child: SciFiPanel(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'HEXFALL',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 10,
                              color: HexfallTheme.cyan,
                              shadows: [Shadow(color: Color(0xB33FE0FF), blurRadius: 24)],
                            ),
                          ),
                          const Text(
                            'PLANETARY SCAN SYSTEM',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, letterSpacing: 4, color: HexfallTheme.textDim),
                          ),
                          const SizedBox(height: 18),
                          if (services.app.hasSavedGame) ...[
                            SciFiButton(
                              label: 'Continue Game',
                              icon: Icons.play_arrow,
                              primary: true,
                              onPressed: () => openGame(context, resume: true),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SciFiButton(
                            label: 'Play Game',
                            icon: Icons.public,
                            primary: !services.app.hasSavedGame,
                            onPressed: () => _push(context, const DifficultyScreen()),
                          ),
                          const SizedBox(height: 10),
                          SciFiButton(label: 'Campaign', icon: Icons.map, onPressed: () => _push(context, const CampaignScreen())),
                          const SizedBox(height: 10),
                          SciFiButton(label: 'Daily Planet', icon: Icons.today, onPressed: () => _push(context, const DailyScreen())),
                          const SizedBox(height: 10),
                          SciFiButton(label: 'Planet Database', icon: Icons.storage, onPressed: () => _push(context, const DatabaseScreen())),
                          const SizedBox(height: 10),
                          SciFiButton(label: 'Statistics', icon: Icons.bar_chart, onPressed: () => _push(context, const StatsScreen())),
                          const SizedBox(height: 10),
                          SciFiButton(label: 'Settings', icon: Icons.settings, onPressed: () => _push(context, const SettingsScreen())),
                        ],
                      ),
                    ),
                  ),
                );
                final w = wide ? 360.0 : (c.maxWidth - 32).clamp(240.0, 420.0);
                return Align(
                  alignment: wide ? Alignment.centerRight : Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(width: w, child: panel),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Difficulty selection
// =============================================================================

class DifficultyScreen extends StatelessWidget {
  const DifficultyScreen({super.key});

  static const _previews = <Difficulty, (PlanetEnvironment, int)>{
    Difficulty.reconnaissance: (PlanetEnvironment.verdant, 11),
    Difficulty.exploration: (PlanetEnvironment.oceanic, 22),
    Difficulty.deepSpace: (PlanetEnvironment.desert, 33),
    Difficulty.anomaly: (PlanetEnvironment.volcanic, 44),
  };

  @override
  Widget build(BuildContext context) {
    return MenuScreen(
      title: 'Select Exploration Profile',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final d in [Difficulty.reconnaissance, Difficulty.exploration, Difficulty.deepSpace, Difficulty.anomaly])
              _card(context, d),
            _customCard(context),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Difficulty d) {
    final (env, seed) = _previews[d]!;
    final cells = GeodesicCells.of(d.frequency);
    return SizedBox(
      width: 210,
      child: SciFiPanel(
        child: Column(
          children: [
            PlanetPreview(environment: env, seed: seed, size: 110),
            const SizedBox(height: 10),
            Text(d.label.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, color: HexfallTheme.cyan)),
            const SizedBox(height: 4),
            Text('$cells tiles · ${(d.density * 100).round()}% mines',
                style: const TextStyle(fontSize: 12, color: HexfallTheme.textDim)),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: Text(d.blurb, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(height: 8),
            SciFiButton(
              label: 'Launch',
              dense: true,
              primary: true,
              onPressed: () => openGame(context, config: GameSession.randomConfig(difficulty: d)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customCard(BuildContext context) => SizedBox(
        width: 210,
        child: SciFiPanel(
          child: Column(
            children: [
              const SizedBox(height: 18),
              const Icon(Icons.tune, size: 64, color: HexfallTheme.cyanSoft),
              const SizedBox(height: 22),
              const Text('CUSTOM',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, color: HexfallTheme.cyan)),
              const SizedBox(height: 4),
              const Text('Your own size and density', style: TextStyle(fontSize: 12, color: HexfallTheme.textDim)),
              const SizedBox(height: 40),
              SciFiButton(
                label: 'Configure',
                dense: true,
                onPressed: () => _push(context, const CustomGameScreen()),
              ),
            ],
          ),
        ),
      );
}

/// Cell-count helper without importing the geometry layer everywhere.
class GeodesicCells {
  const GeodesicCells._();
  static int of(int frequency) => 10 * frequency * frequency + 2;
}

// =============================================================================
// Custom game
// =============================================================================

class CustomGameScreen extends StatefulWidget {
  const CustomGameScreen({super.key});

  @override
  State<CustomGameScreen> createState() => _CustomGameScreenState();
}

class _CustomGameScreenState extends State<CustomGameScreen> {
  double _freq = 10;
  double _density = 0.12;
  PlanetEnvironment? _env; // null = random
  PlanetAnomaly _anomaly = PlanetAnomaly.none;

  @override
  Widget build(BuildContext context) {
    final f = _freq.round();
    final problem = GameConfig.validateCustom(f, _density);
    final cells = GeodesicCells.of(f);
    final mines = (cells * _density).round().clamp(1, cells - 13);
    return MenuScreen(
      title: 'Custom Planet',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SciFiPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GRID FREQUENCY  n = $f', style: const TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              Slider(
                min: GameConfig.customMinFrequency.toDouble(),
                max: GameConfig.customMaxFrequency.toDouble(),
                divisions: GameConfig.customMaxFrequency - GameConfig.customMinFrequency,
                value: _freq,
                label: '$f',
                onChanged: (v) => setState(() => _freq = v),
              ),
              Text('MINE DENSITY  ${(_density * 100).round()}%',
                  style: const TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              Slider(
                min: GameConfig.customMinDensity,
                max: GameConfig.customMaxDensity,
                divisions: ((GameConfig.customMaxDensity - GameConfig.customMinDensity) * 100).round(),
                value: _density,
                label: '${(_density * 100).round()}%',
                onChanged: (v) => setState(() => _density = v),
              ),
              const SizedBox(height: 6),
              const Text('ENVIRONMENT', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(label: const Text('Random'), selected: _env == null, onSelected: (_) => setState(() => _env = null)),
                  for (final e in PlanetEnvironment.values)
                    ChoiceChip(label: Text(e.label), selected: _env == e, onSelected: (_) => setState(() => _env = e)),
                ],
              ),
              const SizedBox(height: 12),
              const Text('ANOMALY (cosmetic only)', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final a in PlanetAnomaly.values)
                    ChoiceChip(label: Text(a.label), selected: _anomaly == a, onSelected: (_) => setState(() => _anomaly = a)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Estimated: $cells tiles (12 pentagons + ${cells - 12} hexagons) · $mines mines',
                style: const TextStyle(color: HexfallTheme.cyanSoft),
              ),
              if (problem != null) Text(problem, style: const TextStyle(color: HexfallTheme.danger)),
              const SizedBox(height: 12),
              SciFiButton(
                label: 'Launch',
                icon: Icons.rocket_launch,
                primary: true,
                onPressed: problem != null
                    ? null
                    : () => openGame(
                          context,
                          config: GameSession.randomConfig(
                            difficulty: Difficulty.custom,
                            frequency: f,
                            density: double.parse(_density.toStringAsFixed(2)),
                            environment: _env,
                            anomaly: _anomaly,
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Campaign
// =============================================================================

class CampaignScreen extends StatelessWidget {
  const CampaignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ServicesScope.of(context).app;
    return MenuScreen(
      title: 'Campaign',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: CampaignData.sectors.length,
          itemBuilder: (context, si) {
            final sector = CampaignData.sectors[si];
            final unlocked = app.isSectorUnlocked(si);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SciFiPanel(
                border: unlocked ? null : HexfallTheme.textDim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(sector.title.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, color: HexfallTheme.cyan)),
                        ),
                        Text('${app.completedInSector(si)}/${sector.missions.length}',
                            style: const TextStyle(color: HexfallTheme.textDim)),
                      ],
                    ),
                    Text(sector.tagline, style: const TextStyle(fontSize: 12, color: HexfallTheme.textDim)),
                    if (!unlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.lock, size: 16, color: HexfallTheme.amber),
                            const SizedBox(width: 6),
                            Text(
                              'Complete ${sector.requiredFromPrevious} missions in the previous sector to unlock.',
                              style: const TextStyle(color: HexfallTheme.amber, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var mi = 0; mi < sector.missions.length; mi++)
                          _missionTile(context, app, si, mi),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _missionTile(BuildContext context, AppState app, int si, int mi) {
    final m = CampaignData.sectors[si].missions[mi];
    final unlocked = app.isMissionUnlocked(si, mi);
    final rec = app.campaign[m.id];
    return Opacity(
      opacity: unlocked ? 1 : 0.4,
      child: InkWell(
        onTap: unlocked ? () => _showMission(context, m, rec?.medal ?? Medal.none, rec?.bestMs) : null,
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(8),
          decoration: sciFiDecoration(fill: const Color(0x66000000)),
          child: Column(
            children: [
              PlanetPreview(environment: m.environment, seed: m.seed, size: 64),
              const SizedBox(height: 4),
              Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${GeodesicCells.of(m.frequency)} tiles', style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim)),
              const SizedBox(height: 2),
              rec == null
                  ? Icon(unlocked ? Icons.radio_button_unchecked : Icons.lock, size: 18, color: HexfallTheme.textDim)
                  : MedalBadge(medal: rec.medal),
            ],
          ),
        ),
      ),
    );
  }

  void _showMission(BuildContext context, Mission m, Medal medal, int? bestMs) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(m.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: PlanetPreview(environment: m.environment, seed: m.seed, size: 110)),
            const SizedBox(height: 10),
            Text(m.briefing),
            const SizedBox(height: 8),
            Text('${m.environment.label} · ${GeodesicCells.of(m.frequency)} tiles · ${(m.density * 100).round()}% mines',
                style: const TextStyle(color: HexfallTheme.textDim, fontSize: 12)),
            if (m.anomaly != PlanetAnomaly.none)
              Text('Anomaly: ${m.anomaly.label}', style: const TextStyle(color: HexfallTheme.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            Text(MedalRules.bronzeText, style: const TextStyle(fontSize: 12)),
            Text(MedalRules.silverText, style: const TextStyle(fontSize: 12)),
            Text(MedalRules.goldText(m.toConfig()), style: const TextStyle(fontSize: 12)),
            if (bestMs != null) ...[
              const SizedBox(height: 8),
              Row(children: [MedalBadge(medal: medal), const SizedBox(width: 6), Text('Best ${formatTime(bestMs)}')]),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openGame(context, config: m.toConfig());
            },
            child: const Text('Begin mission'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Daily planet
// =============================================================================

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ServicesScope.of(context).app;
    final now = DateTime.now().toUtc();
    final cfg = DailyPlanet.forDate(now);
    final key = cfg.dailyDate!;
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    final left = next.difference(now);
    return MenuScreen(
      title: 'Daily Planet',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final rec = app.daily[key];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SciFiPanel(
              child: Column(
                children: [
                  Text(key, style: const TextStyle(fontSize: 18, letterSpacing: 3, color: HexfallTheme.cyan, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Same planet for everyone · new planet in ${left.inHours}h ${left.inMinutes % 60}m (UTC)',
                      style: const TextStyle(fontSize: 12, color: HexfallTheme.textDim)),
                  const SizedBox(height: 14),
                  PlanetPreview(environment: cfg.environment, seed: cfg.seed, size: 150),
                  const SizedBox(height: 10),
                  Text('${cfg.environment.label} world · ${cfg.cellCount} tiles · ${cfg.mineCount} mines'),
                  if (cfg.anomaly != PlanetAnomaly.none)
                    Text('Anomaly: ${cfg.anomaly.label}', style: const TextStyle(color: HexfallTheme.textDim, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (rec == null)
                    const Text('Not attempted yet today.', style: TextStyle(color: HexfallTheme.textDim))
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (rec.completed) ...[
                          MedalBadge(medal: rec.medal, size: 28),
                          const SizedBox(width: 8),
                          Text('Completed in ${formatTime(rec.bestMs)} · ${rec.attempts} attempt(s)'),
                        ] else
                          Text('${rec.attempts} attempt(s) so far — not completed'),
                      ],
                    ),
                  const SizedBox(height: 16),
                  SciFiButton(
                    label: rec == null ? 'Begin' : 'Play again',
                    icon: Icons.rocket_launch,
                    primary: true,
                    onPressed: () => openGame(context, config: cfg),
                  ),
                  const SizedBox(height: 8),
                  const Text('Works fully offline. Online leaderboards may come later.',
                      style: TextStyle(fontSize: 11, color: HexfallTheme.textDim)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
