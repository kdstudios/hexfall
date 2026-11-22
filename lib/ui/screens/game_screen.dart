import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/game/game_config.dart';
import '../../core/game/game_engine.dart';
import '../../core/game/medals.dart';
import '../../core/planet/planet_environment.dart';
import '../../data/campaign_data.dart';
import '../../game/game_session.dart';
import '../../persistence/models.dart';
import '../../render/globe_controller.dart';
import '../../render/globe_view.dart';
import '../../theme/hexfall_theme.dart';
import '../widgets/medal_badge.dart';
import '../widgets/mini_map.dart';
import '../widgets/sci_fi.dart';
import 'info_screens.dart';

/// Opens the game screen with a new [config], or resumes the saved game.
Future<void> openGame(BuildContext context, {GameConfig? config, bool resume = false}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameScreen(config: config, resume: resume)),
    );

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.config, this.resume = false});

  final GameConfig? config;
  final bool resume;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late Services _services;
  late GameSession _session;
  bool _initialised = false;
  Timer? _clockTimer;
  final ValueNotifier<int> _clock = ValueNotifier<int>(0);
  final FocusNode _focus = FocusNode();
  bool _showTuner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    _services = ServicesScope.of(context);
    _session = GameSession(
      app: _services.app,
      globe: _services.gameGlobe,
      audio: _services.audio,
      haptics: _services.haptics,
    );
    var started = false;
    if (widget.resume) started = _session.resumeSaved();
    if (!started) {
      _session.startNew(widget.config ?? GameSession.randomConfig(difficulty: Difficulty.exploration));
    }
    _clockTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _clock.value++);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _session.pause(); // also saves
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    if (!_session.isOver) {
      _session.pause();
    }
    _session.dispose();
    _services.gameGlobe.detachEngine();
    _clock.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.keyR) {
      _session.setMode(InputMode.reveal);
    } else if (k == LogicalKeyboardKey.keyF) {
      _session.setMode(InputMode.flag);
    } else if (k == LogicalKeyboardKey.space) {
      _services.gameGlobe.recenter();
    } else if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.escape) {
      _session.paused ? _session.resume() : _session.pause();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = _services.app;
    return Scaffold(
      body: Focus(
        autofocus: true,
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: ListenableBuilder(
          listenable: Listenable.merge([_session, app]),
          builder: (context, _) {
            final settings = app.settings;
            return Stack(
              children: [
                Positioned.fill(
                  child: GlobeView(
                    controller: _services.gameGlobe,
                    onTap: _session.tapCell,
                    onSecondary: _session.secondaryCell,
                    longPressEnabled: settings.longPressFlag,
                    holdMenuKind: _session.holdKind,
                    onMenuReveal: _session.revealCell,
                    onMenuFlag: _session.flagCell,
                    onHoldOpen: _services.haptics.medium,
                  ),
                ),
                SafeArea(child: _hud(context, settings.leftHanded, settings.uiScale)),
                if (_showTuner) _tuner(settings),
                if (_session.paused && !_session.isOver) _pauseOverlay(context),
                if (_session.showResults && _session.result != null) _resultsOverlay(context),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HUD
  // ---------------------------------------------------------------------------

  Widget _hud(BuildContext context, bool leftHanded, double scale) {
    final c = _session.config;
    final e = _session.engine;
    final modeText = switch (c.mode) {
      GameMode.quick => c.difficulty.label,
      GameMode.campaign => 'Campaign',
      GameMode.daily => 'Daily Planet',
    };

    final nameBlock = IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _session.appearance.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: HexfallTheme.cyan,
              shadows: [Shadow(color: Color(0x803FE0FF), blurRadius: 12)],
            ),
          ),
          Text('$modeText · ${c.environment.label} · ${c.cellCount} tiles',
              style: const TextStyle(fontSize: 10, color: HexfallTheme.textDim)),
        ],
      ),
    );

    final stats = ValueListenableBuilder<int>(
      valueListenable: _clock,
      builder: (context, _, __) => Wrap(
        spacing: 10,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _statPanel('TIME', formatTime(_session.elapsedMs), HexfallTheme.cyanSoft),
          _statPanel('MINES LEFT', '${e.minesRemaining}', HexfallTheme.amber),
          _statPanel('CLEARED', '${e.percentCleared.toStringAsFixed(0)}%', HexfallTheme.good),
          _statPanel(
            'SHIELD',
            e.shieldAvailable ? 'READY' : 'DOWN',
            e.shieldAvailable ? HexfallTheme.cyan : HexfallTheme.danger,
            icon: e.shieldAvailable ? Icons.shield : Icons.shield_outlined,
          ),
        ],
      ),
    );

    final back = _hudButton(Icons.keyboard_double_arrow_left, 'Pause', _session.pause);

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final controls = Align(
          alignment: leftHanded ? Alignment.bottomLeft : Alignment.bottomCenter,
          child: _controls(scale),
        );
        if (wide) {
          // Concept layout: readouts along the very top, centred.
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [back, const SizedBox(height: 8), nameBlock]),
                ),
                Align(alignment: Alignment.topCenter, child: stats),
                Positioned(right: 0, top: 0, child: MiniMap(controller: _services.gameGlobe)),
                controls,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [back, const SizedBox(width: 10), Expanded(child: nameBlock)]),
              const SizedBox(height: 6),
              stats,
              const Spacer(),
              controls,
            ],
          ),
        );
      },
    );
  }

  /// Live tuning panel for how strongly terrain colours the tiles.
  Widget _tuner(Settings s) {
    final app = _services.app;
    Widget row(String label, double v, ValueChanged<double> onChanged) => Row(
          children: [
            SizedBox(width: 74, child: Text(label, style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: HexfallTheme.cyan))),
            Expanded(
              child: Slider(min: 0, max: 1.2, divisions: 120, value: v.clamp(0.0, 1.2).toDouble(), onChanged: onChanged),
            ),
            SizedBox(
              width: 42,
              child: Text(v.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFE8F8FF))),
            ),
          ],
        );
    double r2(double x) => double.parse(x.toStringAsFixed(2));
    return Positioned(
      left: 10,
      bottom: 84,
      child: SizedBox(
        width: 340,
        child: _framed(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('PLANET COLOUR', style: TextStyle(fontSize: 11, letterSpacing: 2, color: HexfallTheme.textDim)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showTuner = false),
                  ),
                ],
              ),
              row('HIDDEN', s.hiddenTint, (v) => app.updateSettings(s.copyWith(hiddenTint: r2(v)))),
              row('SCANNED', s.scannedTint, (v) => app.updateSettings(s.copyWith(scannedTint: r2(v)))),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => app.updateSettings(
                    s.copyWith(hiddenTint: Settings.defaultHiddenTint, scannedTint: Settings.defaultScannedTint),
                  ),
                  child: Text('Reset (${Settings.defaultHiddenTint.toStringAsFixed(2)} / ${Settings.defaultScannedTint.toStringAsFixed(2)})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thin notched frame used by every HUD readout (see ConceptArt.jpg).
  Widget _framed({required Widget child, Color color = HexfallTheme.cyan, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6)}) =>
      CustomPaint(painter: _HudFrame(color), child: Padding(padding: padding, child: child));

  Widget _statPanel(String label, String value, Color color, {IconData? icon}) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 96),
        child: _framed(
          color: color,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, letterSpacing: 3, color: HexfallTheme.textDim)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 17, color: color), const SizedBox(width: 4)],
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE8F8FF),
                      shadows: [Shadow(color: color.withAlpha(170), blurRadius: 12)],
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _hudButton(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: () {
              _services.audio.ensureStarted();
              onTap();
            },
            child: _framed(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              child: Icon(icon, size: 20, color: HexfallTheme.cyan),
            ),
          ),
        ),
      );

  /// Bottom transport-style control strip, centred like the concept art.
  Widget _controls(double scale) {
    final over = _session.isOver;
    Widget btn(IconData icon, String label, VoidCallback? onTap, {bool selected = false}) {
      final color = onTap == null ? HexfallTheme.textDim : (selected ? HexfallTheme.cyan : HexfallTheme.cyanSoft);
      return Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    _services.audio.ensureStarted();
                    onTap();
                  },
            child: Container(
              width: 64 * scale,
              padding: EdgeInsets.symmetric(vertical: 6 * scale),
              decoration: BoxDecoration(
                color: selected ? HexfallTheme.cyan.withAlpha(34) : null,
                border: Border(
                  bottom: BorderSide(color: selected ? HexfallTheme.cyan : const Color(0x00000000), width: 2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24 * scale, color: color, shadows: selected ? const [Shadow(color: Color(0xAA3FE0FF), blurRadius: 10)] : null),
                  Text(label, style: TextStyle(fontSize: 9 * scale, letterSpacing: 1.5, color: color)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _framed(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.radar, 'REVEAL', over ? null : () => _session.setMode(InputMode.reveal), selected: _session.mode == InputMode.reveal),
          btn(Icons.flag, 'FLAG', over ? null : () => _session.setMode(InputMode.flag), selected: _session.mode == InputMode.flag),
          btn(Icons.center_focus_strong, 'CENTER', () => _services.gameGlobe.camera.reset()),
          btn(Icons.palette, 'TINT', () => setState(() => _showTuner = !_showTuner), selected: _showTuner),
          btn(over ? Icons.assessment : Icons.pause, over ? 'RESULT' : 'PAUSE', over ? _session.reopenResults : _session.pause),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pause menu
  // ---------------------------------------------------------------------------

  Widget _pauseOverlay(BuildContext context) {
    final quick = _session.config.mode == GameMode.quick;
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC020611),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SciFiPanel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('PAUSED',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 8, color: HexfallTheme.cyan)),
                    const SizedBox(height: 4),
                    Text('${_session.appearance.name} · seed ${_session.config.seed}',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim)),
                    const SizedBox(height: 16),
                    SciFiButton(label: 'Resume', icon: Icons.play_arrow, primary: true, onPressed: _session.resume),
                    const SizedBox(height: 8),
                    SciFiButton(
                      label: quick ? 'Restart (new planet)' : 'Restart mission',
                      icon: Icons.refresh,
                      onPressed: () => _session.restart(),
                    ),
                    if (quick) ...[
                      const SizedBox(height: 8),
                      SciFiButton(
                        label: 'Replay same planet',
                        icon: Icons.replay,
                        onPressed: () => _session.restart(sameSeed: true),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SciFiButton(label: 'Settings', icon: Icons.settings, onPressed: () => _settingsDialog(context)),
                    const SizedBox(height: 8),
                    SciFiButton(label: 'Main menu', icon: Icons.home, onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _settingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: ListenableBuilder(
                    listenable: _services.app,
                    builder: (context, _) => SettingsPanel(app: _services.app, showLab: false),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SciFiButton(label: 'Close', dense: true, onPressed: () => Navigator.pop(dialogContext)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  Mission? _nextMission() {
    final id = _session.config.missionId;
    if (id == null) return null;
    for (var si = 0; si < CampaignData.sectors.length; si++) {
      final ms = CampaignData.sectors[si].missions;
      for (var mi = 0; mi < ms.length; mi++) {
        if (ms[mi].id != id) continue;
        if (mi + 1 < ms.length) return ms[mi + 1];
        if (si + 1 < CampaignData.sectors.length && _services.app.isSectorUnlocked(si + 1)) {
          return CampaignData.sectors[si + 1].missions.first;
        }
        return null;
      }
    }
    return null;
  }

  Widget _resultsOverlay(BuildContext context) {
    final r = _session.result!;
    final won = r.won;
    final color = won ? HexfallTheme.good : HexfallTheme.danger;
    final cfg = r.config;
    final out = _session.recordOutcome;
    final next = won ? _nextMission() : null;

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(color: HexfallTheme.textDim))),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );

    Widget req(String text, bool met) => Row(children: [
          Icon(met ? Icons.check_circle : Icons.radio_button_unchecked, size: 15, color: met ? HexfallTheme.good : HexfallTheme.textDim),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
        ]);

    final goldMet = won && !r.shieldUsed && r.incorrectFlags == 0 && r.elapsedMs <= MedalRules.goldTimeTargetMs(cfg);

    return Positioned.fill(
      child: Container(
        color: const Color(0xB3020611),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SciFiPanel(
                border: color,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(won ? 'PLANET CLEARED' : 'PLANET LOST',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 5, color: color)),
                    Text(r.planetName, textAlign: TextAlign.center, style: const TextStyle(color: HexfallTheme.textDim)),
                    const SizedBox(height: 12),
                    if (won)
                      Center(child: Column(children: [MedalBadge(medal: r.medal, size: 56), Text(r.medal.label, style: TextStyle(color: medalColor(r.medal), fontWeight: FontWeight.w800))])),
                    if (out != null && out.newBestTime && won)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('NEW PERSONAL BEST', textAlign: TextAlign.center, style: TextStyle(color: HexfallTheme.amber, fontWeight: FontWeight.w800, letterSpacing: 2)),
                      ),
                    const SizedBox(height: 10),
                    row('Time', formatTime(r.elapsedMs)),
                    row('Cleared', '${r.percentCleared.toStringAsFixed(0)}%'),
                    row('Shield used', r.shieldUsed ? 'Yes' : 'No'),
                    row('Incorrect flags', '${r.incorrectFlags}'),
                    if (won) ...[
                      const Divider(height: 18),
                      req(MedalRules.bronzeText, true),
                      req(MedalRules.silverText, !r.shieldUsed),
                      req(MedalRules.goldText(cfg), goldMet),
                    ],
                    const SizedBox(height: 14),
                    if (next != null) ...[
                      SciFiButton(
                        label: 'Next mission',
                        icon: Icons.arrow_forward,
                        primary: true,
                        onPressed: () => _session.startNew(next.toConfig()),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SciFiButton(
                      label: cfg.mode == GameMode.quick ? 'New planet' : 'Retry',
                      icon: Icons.refresh,
                      primary: next == null,
                      onPressed: () => _session.restart(),
                    ),
                    const SizedBox(height: 8),
                    SciFiButton(label: 'Inspect planet', icon: Icons.visibility, onPressed: _session.inspectPlanet),
                    const SizedBox(height: 8),
                    SciFiButton(label: 'Main menu', icon: Icons.home, onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin notched HUD frame: dark translucent fill, cyan outline, corner cuts
/// and a glowing underline.
class _HudFrame extends CustomPainter {
  _HudFrame(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const cut = 8.0;
    final mid = w / 2;
    final path = Path()
      ..moveTo(0, cut)
      ..lineTo(cut, 0)
      ..lineTo(mid - 16, 0)
      ..lineTo(mid - 10, 4)
      ..lineTo(mid + 10, 4)
      ..lineTo(mid + 16, 0)
      ..lineTo(w - cut, 0)
      ..lineTo(w, cut)
      ..lineTo(w, h - cut)
      ..lineTo(w - cut, h)
      ..lineTo(cut, h)
      ..lineTo(0, h - cut)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0x8A04101C));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = color.withAlpha(190),
    );
    canvas.drawLine(
      Offset(cut + 6, h - 0.5),
      Offset(w - cut - 6, h - 0.5),
      Paint()
        ..strokeWidth = 2.5
        ..color = color.withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  @override
  bool shouldRepaint(_HudFrame old) => old.color != color;
}
