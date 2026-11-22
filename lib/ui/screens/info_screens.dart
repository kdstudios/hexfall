import 'package:flutter/material.dart';

import '../../core/game/game_config.dart';
import '../../core/game/medals.dart';
import '../../core/planet/planet_environment.dart';
import '../../persistence/app_state.dart';
import '../../persistence/models.dart';
import '../../render/glyph_cache.dart';
import '../../theme/hexfall_theme.dart';
import '../widgets/medal_badge.dart';
import '../widgets/sci_fi.dart';
import 'game_screen.dart';
import 'globe_lab_screen.dart';
import 'sound_screen.dart';

// =============================================================================
// Planet database
// =============================================================================

class DatabaseScreen extends StatelessWidget {
  const DatabaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ServicesScope.of(context).app;
    return MenuScreen(
      title: 'Planet Database',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final entries = app.planets.values.toList()..sort((a, b) => b.discovered.compareTo(a.discovered));
          if (entries.isEmpty) {
            return const Center(
              child: Text('No planets surveyed yet.\nExplore a world to add it here.',
                  textAlign: TextAlign.center, style: TextStyle(color: HexfallTheme.textDim)),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [for (final e in entries) _card(context, e)],
            ),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, PlanetEntry e) => InkWell(
        onTap: () => _detail(context, e),
        child: Container(
          width: 190,
          padding: const EdgeInsets.all(10),
          decoration: sciFiDecoration(glow: 0.5),
          child: Column(
            children: [
              PlanetPreview(environment: e.environment, seed: e.seed, size: 92),
              const SizedBox(height: 6),
              Text(e.name, style: const TextStyle(fontWeight: FontWeight.w800, color: HexfallTheme.cyan)),
              Text('${e.environment.label} · ${e.difficulty.label}',
                  style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (e.completed) ...[MedalBadge(medal: e.medal), const SizedBox(width: 4), Text(formatTime(e.bestMs), style: const TextStyle(fontSize: 12))]
                  else
                    const Text('Not completed', style: TextStyle(fontSize: 12, color: HexfallTheme.amber)),
                ],
              ),
            ],
          ),
        ),
      );

  void _detail(BuildContext context, PlanetEntry e) {
    final d = e.discovered.toLocal();
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(e.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: PlanetPreview(environment: e.environment, seed: e.seed, size: 120)),
            const SizedBox(height: 10),
            Text('Environment: ${e.environment.label}'),
            Text('Difficulty: ${e.difficulty.label}'),
            Text('Seed: ${e.seed}'),
            Text('Grid: n=${e.frequency} (${10 * e.frequency * e.frequency + 2} tiles)'),
            Text('Mine density: ${(e.density * 100).round()}%'),
            if (e.anomaly != PlanetAnomaly.none) Text('Anomaly: ${e.anomaly.label}'),
            Text('Discovered: $date'),
            Text(e.completed ? 'Completed in ${formatTime(e.bestMs)}' : 'Not completed yet'),
            Row(children: [const Text('Medal: '), MedalBadge(medal: e.medal), Text(' ${e.medal.label}')]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openGame(
                context,
                config: GameConfig(
                  frequency: e.frequency,
                  mineDensity: e.density,
                  seed: e.seed,
                  environment: e.environment,
                  anomaly: e.anomaly,
                  difficulty: e.difficulty,
                  mode: GameMode.quick,
                ),
              );
            },
            child: const Text('Revisit planet'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Statistics
// =============================================================================

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ServicesScope.of(context).app;
    return MenuScreen(
      title: 'Statistics',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final s = app.stats;
          Widget row(String k, String v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(k, style: const TextStyle(color: HexfallTheme.textDim))),
                  Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SciFiPanel(
                  child: Column(children: [
                    row('Games played', '${s.gamesPlayed}'),
                    row('Planets completed', '${s.completed}'),
                    row('Planets lost', '${s.lost}'),
                    row('Mines discovered', '${s.minesDiscovered}'),
                    row('Shields used', '${s.shieldsUsed}'),
                    row('Total exploration time', formatTime(s.totalTimeMs)),
                  ]),
                ),
                const SizedBox(height: 12),
                SciFiPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MEDALS', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800, color: HexfallTheme.cyan)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (final m in [Medal.bronze, Medal.silver, Medal.gold])
                            Column(children: [MedalBadge(medal: m, size: 34), Text('${s.medalCounts[m.index - 1]}')]),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SciFiPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BEST RESULTS', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800, color: HexfallTheme.cyan)),
                      const SizedBox(height: 6),
                      for (final d in Difficulty.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(d.label)),
                            if (s.bestTimesMs[d.name] != null) ...[
                              MedalBadge(medal: Medal.values[s.bestMedal[d.name] ?? 0], size: 18),
                              const SizedBox(width: 6),
                              Text(formatTime(s.bestTimesMs[d.name]!)),
                            ] else
                              const Text('—', style: TextStyle(color: HexfallTheme.textDim)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Settings
// =============================================================================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ServicesScope.of(context).app;
    return MenuScreen(
      title: 'Settings',
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SettingsPanel(app: app),
        ),
      ),
    );
  }
}

/// Reusable settings controls (also shown from the in-game pause menu).
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.app, this.showLab = true});

  final AppState app;
  final bool showLab;

  Settings get s => app.settings;
  void _apply(Settings v) => app.updateSettings(v);

  Widget _slider(String label, double value, ValueChanged<double> onChanged, {double min = 0, double max = 1}) => Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(child: Slider(min: min, max: max, value: value.clamp(min, max).toDouble(), onChanged: onChanged)),
        ],
      );

  Widget _switch(String label, String? sub, bool v, ValueChanged<bool> onChanged) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 11)),
        value: v,
        onChanged: onChanged,
      );

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800, color: HexfallTheme.cyan, fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final st = s;
    return SciFiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('Audio'),
          _slider('Master', st.masterVolume, (v) => _apply(st.copyWith(masterVolume: v))),
          _slider('Music', st.musicVolume, (v) => _apply(st.copyWith(musicVolume: v))),
          _slider('Effects', st.sfxVolume, (v) => _apply(st.copyWith(sfxVolume: v))),
          _slider('Ambient', st.ambientVolume, (v) => _apply(st.copyWith(ambientVolume: v))),
          _switch('Mute all', null, st.muted, (v) => _apply(st.copyWith(muted: v))),
          _switch('Haptic feedback', 'Vibration on supported phones', st.haptics, (v) => _apply(st.copyWith(haptics: v))),
          const SizedBox(height: 8),
          SciFiButton(
            label: 'Sound library · import / export',
            icon: Icons.library_music,
            dense: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SoundLibraryScreen())),
          ),
          _heading('Accessibility'),
          const Text('Number colours', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final (label, p) in const [
                ('Standard', NumberPalette.standard),
                ('Colour-blind friendly', NumberPalette.colorBlind),
                ('High contrast', NumberPalette.highContrast),
              ])
                ChoiceChip(label: Text(label), selected: st.palette == p, onSelected: (_) => _apply(st.copyWith(palette: p))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var n = 1; n <= 8; n++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('$n',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(NumberPalettes.of(st.palette)[n]))),
                ),
            ],
          ),
          _switch('Reduced motion', 'No shaking, flashing, big camera moves or intense scans', st.reducedMotion,
              (v) => _apply(st.copyWith(reducedMotion: v))),
          _slider('Interface size', st.uiScale, (v) => _apply(st.copyWith(uiScale: double.parse(v.toStringAsFixed(2)))), min: 0.8, max: 1.4),
          _switch('Left-handed layout', 'Moves game controls to the left', st.leftHanded, (v) => _apply(st.copyWith(leftHanded: v))),
          _heading('Controls'),
          _switch('Touch hold menu', 'Hold a tile, then drag up to Reveal or down to Flag. Turn off to use the Reveal / Flag buttons only', st.longPressFlag,
              (v) => _apply(st.copyWith(longPressFlag: v))),
          const Text('Desktop: left-click reveal · right-click flag · drag rotate · wheel zoom · R / F modes · Space recenter · P pause.',
              style: TextStyle(fontSize: 11, color: HexfallTheme.textDim)),
          _heading('Visuals'),
          Wrap(
            spacing: 8,
            children: [
              for (final q in RenderQuality.values)
                ChoiceChip(
                  label: Text(q == RenderQuality.auto ? 'Auto (adapts to your device)' : '${q.name[0].toUpperCase()}${q.name.substring(1)} quality'),
                  selected: st.quality == q,
                  onSelected: (_) => _apply(st.copyWith(quality: q)),
                ),
            ],
          ),
          _switch('Anomaly effects', 'Cosmetic haze / flashes. Never changes gameplay', st.anomalyEffects,
              (v) => _apply(st.copyWith(anomalyEffects: v))),
          _switch('Scan-line effect', null, st.scanEffects, (v) => _apply(st.copyWith(scanEffects: v))),
          _heading('Planet look'),
          _slider('Hidden tiles', st.hiddenTint, (v) => _apply(st.copyWith(hiddenTint: double.parse(v.toStringAsFixed(2)))), max: 1.2),
          _slider('Scanned tiles', st.scannedTint, (v) => _apply(st.copyWith(scannedTint: double.parse(v.toStringAsFixed(2)))), max: 1.2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Colour strength ${st.hiddenTint.toStringAsFixed(2)} hidden · ${st.scannedTint.toStringAsFixed(2)} scanned. 0 = plain metal.',
              style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim),
            ),
          ),
          TextButton(
            onPressed: () => _apply(st.copyWith(hiddenTint: Settings.defaultHiddenTint, scannedTint: Settings.defaultScannedTint)),
            child: const Text('Reset colour strength'),
          ),
          _switch('Tile thickness', 'Raised tile sides near the edge of the planet', st.depthWalls, (v) => _apply(st.copyWith(depthWalls: v))),
          _switch('Edge highlights', 'Soft glints on tile edges facing the sun', st.depthEdges, (v) => _apply(st.copyWith(depthEdges: v))),
          _switch('Plate relief', 'Extra bevel and depth in the tile artwork', st.depthRelief, (v) => _apply(st.copyWith(depthRelief: v))),
          if (showLab) ...[
            _heading('Developer'),
            SciFiButton(
              label: 'Geometry lab',
              icon: Icons.science,
              dense: true,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GlobeLabScreen())),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Saves are stored on this device (browser: local storage, which clears if you wipe site data).',
            style: TextStyle(fontSize: 11, color: HexfallTheme.textDim),
          ),
        ],
      ),
    );
  }
}
