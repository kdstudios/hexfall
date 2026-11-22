import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/geometry/geodesic_grid.dart';
import '../render/globe_controller.dart';
import '../render/globe_view.dart';
import '../theme/hexfall_theme.dart';

/// Milestone 1 screen: the rotatable geodesic globe plus an inspector and
/// controls for verifying the geometry. Replaced by the real menu / HUD in
/// later milestones, but the GlobeView inside it stays.
class GlobeSandboxScreen extends StatefulWidget {
  const GlobeSandboxScreen({super.key});

  @override
  State<GlobeSandboxScreen> createState() => _GlobeSandboxScreenState();
}

class _GlobeSandboxScreenState extends State<GlobeSandboxScreen> {
  late final GlobeController _controller;
  bool _panelOpen = true;

  static const _presets = <(String, int)>[
    ('Recon', 4),
    ('Explore', 8),
    ('Deep Space', 10),
    ('Anomaly', 16),
  ];

  @override
  void initState() {
    super.initState();
    _controller = GlobeController(frequency: 8);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: GlobeView(controller: _controller)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  const Spacer(),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_controller.selected >= 0) _infoCard(),
                            if (_controller.selected >= 0) const SizedBox(height: 8),
                            _controlPanel(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Top bar ---------------------------------------------------------------------

  Widget _topBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'HEXFALL',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: HexfallTheme.cyan,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'MILESTONE 1 · GEODESIC GLOBE',
                  style: TextStyle(fontSize: 11, letterSpacing: 2, color: HexfallTheme.textDim),
                ),
                SizedBox(height: 6),
                Text(
                  'Drag: rotate   Wheel / pinch: zoom\nTap / click: select   Long-press / right-click: mark',
                  style: TextStyle(fontSize: 11, height: 1.35, color: HexfallTheme.textDim),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<GlobeStats>(
          valueListenable: _controller.stats,
          builder: (context, s, _) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: _glass(),
            child: Text(
              '${s.fps.toStringAsFixed(0)} fps · ${s.paintMs.toStringAsFixed(1)} ms · ${s.visibleCells} tiles',
              style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim),
            ),
          ),
        ),
      ],
    );
  }

  // --- Inspector -------------------------------------------------------------------

  Widget _infoCard() {
    final cell = _controller.grid.cells[_controller.selected];
    final lat = math.asin(cell.position.y.clamp(-1.0, 1.0)) * 180 / math.pi;
    final lon = math.atan2(cell.position.x, cell.position.z) * 180 / math.pi;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'CELL #${cell.id} · ${cell.isPentagon ? 'PENTAGON' : 'HEXAGON'} · ${cell.sides} neighbours',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: cell.isPentagon ? HexfallTheme.magenta : HexfallTheme.cyan,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Deselect',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _controller.select(-1),
              ),
            ],
          ),
          Text(
            'lat ${lat.toStringAsFixed(1)}°   lon ${lon.toStringAsFixed(1)}°',
            style: const TextStyle(fontSize: 12, color: HexfallTheme.textDim),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final nb in cell.neighbours)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '#$nb${_controller.grid.sidesOf(nb) == 5 ? ' ⬠' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    _controller.select(nb);
                    _controller.recenter();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Controls --------------------------------------------------------------------

  Widget _controlPanel(BuildContext context) {
    final c = _controller;
    final n = c.frequency;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: _glass(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'FREQUENCY n=$n · ${GeodesicGrid.cellCountFor(n)} cells · 12 pentagons + '
                  '${GeodesicGrid.cellCountFor(n) - 12} hexagons',
                  style: const TextStyle(fontSize: 12, letterSpacing: 0.5, fontWeight: FontWeight.w600),
                ),
              ),
              _validationChip(context),
              IconButton(
                tooltip: _panelOpen ? 'Collapse' : 'Expand',
                visualDensity: VisualDensity.compact,
                icon: Icon(_panelOpen ? Icons.expand_more : Icons.expand_less),
                onPressed: () => setState(() => _panelOpen = !_panelOpen),
              ),
            ],
          ),
          if (_panelOpen) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (label, freq) in _presets)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('$label · ${GeodesicGrid.cellCountFor(freq)}'),
                    selected: n == freq,
                    onSelected: (_) => c.setFrequency(freq),
                  ),
              ],
            ),
            Row(
              children: [
                const Text('n', style: TextStyle(color: HexfallTheme.textDim)),
                Expanded(
                  child: Slider(
                    min: GeodesicGrid.minFrequency.toDouble(),
                    max: GeodesicGrid.maxFrequency.toDouble(),
                    divisions: GeodesicGrid.maxFrequency - GeodesicGrid.minFrequency,
                    value: n.toDouble(),
                    label: '$n',
                    onChanged: (v) => c.setFrequency(v.round()),
                  ),
                ),
                Text(
                  'built in ${c.generationMs.toStringAsFixed(0)} ms',
                  style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Pentagons'),
                  selected: c.showPentagons,
                  onSelected: c.setShowPentagons,
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Scan line'),
                  selected: c.scanEffect,
                  onSelected: c.setScanEffect,
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Glow'),
                  selected: c.outlineGlow,
                  onSelected: c.setOutlineGlow,
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Auto-rotate'),
                  selected: c.autoRotate,
                  onSelected: c.setAutoRotate,
                ),
                FilledButton.tonalIcon(
                  onPressed: c.recenter,
                  icon: const Icon(Icons.center_focus_strong, size: 18),
                  label: Text(c.selected >= 0 ? 'Recenter on cell' : 'Reset camera'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _validationChip(BuildContext context) {
    final report = _controller.report;
    final ok = report.passed;
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        ok ? Icons.verified : Icons.error,
        size: 16,
        color: ok ? HexfallTheme.good : HexfallTheme.danger,
      ),
      label: Text(
        ok ? 'Geometry OK' : '${report.failureCount} FAILED',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Grid validation · n=${_controller.frequency}'),
          content: SizedBox(
            width: 460,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final check in report.checks)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      check.passed ? Icons.check_circle : Icons.cancel,
                      color: check.passed ? HexfallTheme.good : HexfallTheme.danger,
                      size: 20,
                    ),
                    title: Text(check.name),
                    subtitle: Text(check.detail),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  BoxDecoration _glass() => BoxDecoration(
        color: HexfallTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HexfallTheme.cyan.withAlpha(70)),
      );
}
