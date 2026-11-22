import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'globe_controller.dart';
import 'globe_painter.dart';

/// The interactive planet. Handles every input method with raw pointer events
/// so we can reliably tell these apart:
///
///  * drag (rotate)            – touch or left mouse button, after a small slop
///  * tap / left click         – select a tile
///  * long press / right click – "secondary" action (flag in Milestone 2)
///  * pinch / wheel / trackpad – zoom
///
/// A tap only fires if the pointer never moved past the slop distance and no
/// second finger ever joined, so rotating or pinching can never select a tile.
class GlobeView extends StatefulWidget {
  const GlobeView({
    super.key,
    required this.controller,
    this.onTap,
    this.onSecondary,
    this.longPressEnabled = true,
    this.interactive = true,
    this.holdMenuKind,
    this.onMenuReveal,
    this.onMenuFlag,
    this.onHoldOpen,
  });

  final GlobeController controller;

  /// Called with the tapped / left-clicked cell id (never while rotating).
  final void Function(int cell)? onTap;

  /// Called for long-press (touch) or right-click (mouse).
  final void Function(int cell)? onSecondary;
  final bool longPressEnabled;

  /// When false the globe ignores all input (menu background).
  final bool interactive;

  /// Touch hold menu. If [holdMenuKind] is set, touching and holding a tile
  /// opens a menu: drag up to Reveal, drag down to Flag / Unflag, release to
  /// confirm (release in the middle cancels). If null, a long press simply
  /// calls [onSecondary].
  final HoldMenuKind Function(int cell)? holdMenuKind;
  final void Function(int cell)? onMenuReveal;
  final void Function(int cell)? onMenuFlag;
  final VoidCallback? onHoldOpen;

  @override
  State<GlobeView> createState() => _GlobeViewState();
}

class _GlobeViewState extends State<GlobeView> with SingleTickerProviderStateMixin {
  static const double _touchSlop = 12;
  static const double _mouseSlop = 5;
  static const Duration _longPress = Duration(milliseconds: 320);

  late final Ticker _ticker;
  late final GlobePainter _painter;
  Duration _lastTick = Duration.zero;
  double _fpsAccum = 0;
  int _fpsFrames = 0;

  Size _size = Size.zero;

  // Active pointers.
  final Map<int, Offset> _pointers = <int, Offset>{};

  // Single-pointer gesture state.
  int? _primaryId;
  Offset _downPos = Offset.zero;
  Offset _lastPos = Offset.zero;
  Duration _lastMoveTime = Duration.zero;
  bool _dragging = false;
  bool _secondaryButton = false;
  bool _longPressFired = false;
  bool _consumed = false; // pinch happened: ignore tap/drag until all lifted
  bool _mouse = false;
  bool _menuOpen = false;
  Timer? _longPressTimer;

  // Pinch state.
  double _lastPinchDistance = 0;

  // Trackpad pan/zoom state.
  double _lastPanZoomScale = 1;

  GlobeController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _painter = GlobePainter(_c);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _c.holdMenu = null;
    _ticker.dispose();
    _painter.disposeLayers();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _lastTick).inMicroseconds / 1e6);
    _lastTick = elapsed;
    _c.time = elapsed.inMicroseconds / 1e6;

    final effectsChanged = _c.update();
    final holding = _pointers.isNotEmpty;
    final moved = _c.camera.tick(
      dt,
      idleSpin: _c.autoRotate && !_c.reducedMotion ? 0.12 : 0,
      userHolding: holding,
    );
    if (moved || _c.scanEffect || _c.camera.isAnimating || effectsChanged || _c.hasActiveEffects) {
      _c.frame.value++;
    }

    _fpsAccum += dt;
    _fpsFrames++;
    if (_fpsAccum >= 0.5) {
      _c.stats.value = GlobeStats(
        fps: _fpsFrames / _fpsAccum,
        paintMs: _c.renderer.lastPaintMs,
        visibleCells: _c.renderer.visibleCells,
      );
      _c.reportFps(_fpsFrames / _fpsAccum);
      _fpsAccum = 0;
      _fpsFrames = 0;
    }
  }

  // --- Pointer handling -----------------------------------------------------------

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _c.camera.grab();

    if (_pointers.length == 1) {
      _primaryId = e.pointer;
      _downPos = e.localPosition;
      _lastPos = e.localPosition;
      _lastMoveTime = e.timeStamp;
      _dragging = false;
      _longPressFired = false;
      _consumed = false;
      _mouse = e.kind == PointerDeviceKind.mouse;
      _secondaryButton = _mouse && (e.buttons & kSecondaryMouseButton) != 0;

      _longPressTimer?.cancel();
      if (widget.longPressEnabled && !_secondaryButton) {
        _longPressTimer = Timer(_longPress, _fireLongPress);
      }
    } else {
      // A second finger: this is a pinch. Cancel any tap / long press / menu.
      _closeMenu();
      _consumed = true;
      _longPressTimer?.cancel();
      _lastPinchDistance = _pinchDistance();
    }
  }

  void _fireLongPress() {
    if (_primaryId == null || _dragging || _consumed || _pointers.length != 1) return;
    final id = _c.pick(_downPos, _size);
    if (id < 0) return;

    final kindFn = widget.holdMenuKind;
    if (kindFn == null) {
      _longPressFired = true;
      widget.onSecondary?.call(id);
      return;
    }
    final kind = kindFn(id);
    if (kind == HoldMenuKind.none) return;

    final anchor = _c.renderer.cellScreenPosition(id) ?? _downPos;
    final r = _c.renderer.cellScreenRadius(id);
    _c.holdMenu = HoldMenu(
      cell: id,
      anchor: anchor,
      kind: kind,
      distance: (r * 2.0).clamp(66.0, 110.0).toDouble(),
      cellRadius: r,
      start: _c.time,
    );
    _menuOpen = true;
    _longPressFired = true; // releasing must not also count as a tap
    widget.onHoldOpen?.call();
    _c.frame.value++;
  }

  void _closeMenu() {
    if (!_menuOpen && _c.holdMenu == null) return;
    _menuOpen = false;
    _c.holdMenu = null;
    _c.frame.value++;
  }

  void _updateMenu(Offset pos) {
    final m = _c.holdMenu;
    if (m == null) return;
    final dy = pos.dy - m.anchor.dy;
    final dx = pos.dx - m.anchor.dx;
    final threshold = m.distance * 0.55;
    var h = 0;
    if (dx.abs() < 160) {
      if (dy < -threshold) {
        h = -1;
      } else if (dy > threshold && m.kind != HoldMenuKind.number) {
        h = 1;
      }
    }
    if (h != m.highlight) {
      m.highlight = h;
      _c.frame.value++;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_menuOpen && e.pointer == _primaryId) {
      _updateMenu(e.localPosition); // the hold menu owns the drag, not rotation
      return;
    }
    if (_pointers.length >= 2) {
      _handlePinch();
      return;
    }
    if (e.pointer != _primaryId || _consumed || _secondaryButton) return;

    final pos = e.localPosition;
    if (!_dragging) {
      final slop = _mouse ? _mouseSlop : _touchSlop;
      if ((pos - _downPos).distance > slop) {
        _dragging = true;
        _longPressTimer?.cancel();
        _lastPos = _downPos; // apply the slop distance too: no initial lag
      } else {
        return;
      }
    }

    final delta = pos - _lastPos;
    _lastPos = pos;
    _c.camera.dragBy(delta.dx, delta.dy, _size);

    // Track angular velocity for inertia.
    final dtMicro = (e.timeStamp - _lastMoveTime).inMicroseconds;
    _lastMoveTime = e.timeStamp;
    if (dtMicro > 0) {
      final dt = dtMicro / 1e6;
      final k = 1.0 / _c.camera.projection(_size).radiusPx;
      final vx = (delta.dy * k) / dt;
      final vy = (delta.dx * k) / dt;
      _c.camera.spinX = _c.camera.spinX * 0.5 + vx * 0.5;
      _c.camera.spinY = _c.camera.spinY * 0.5 + vy * 0.5;
    }
    _c.frame.value++;
  }

  void _handlePinch() {
    final d = _pinchDistance();
    if (_lastPinchDistance > 0 && d > 0) {
      _c.camera.zoomBy(d / _lastPinchDistance);
      _c.frame.value++;
    }
    _lastPinchDistance = d;
  }

  double _pinchDistance() {
    if (_pointers.length < 2) return 0;
    final it = _pointers.values.iterator..moveNext();
    final a = it.current;
    it.moveNext();
    final b = it.current;
    return (a - b).distance;
  }

  void _onUp(PointerUpEvent e) {
    final wasPrimary = e.pointer == _primaryId;
    final tapCandidate = wasPrimary &&
        !_dragging &&
        !_consumed &&
        !_longPressFired &&
        _pointers.length == 1;
    final secondary = _secondaryButton;
    if (_menuOpen && wasPrimary) {
      final m = _c.holdMenu;
      _closeMenu();
      _pointers.remove(e.pointer);
      _longPressTimer?.cancel();
      if (m != null) {
        if (m.highlight == -1) {
          widget.onMenuReveal?.call(m.cell);
        } else if (m.highlight == 1) {
          widget.onMenuFlag?.call(m.cell);
        }
      }
      if (_pointers.isEmpty) {
        _primaryId = null;
        _dragging = false;
        _consumed = false;
        _secondaryButton = false;
      }
      _c.frame.value++;
      return;
    }
    // If the finger paused before lifting, don't fling on stale velocity.
    if (wasPrimary && _dragging && (e.timeStamp - _lastMoveTime).inMilliseconds > 90) {
      _c.camera.spinX = 0;
      _c.camera.spinY = 0;
    }
    _pointers.remove(e.pointer);
    _longPressTimer?.cancel();

    if (tapCandidate) {
      final id = _c.pick(e.localPosition, _size);
      if (id >= 0) {
        if (secondary) {
          widget.onSecondary?.call(id);
        } else {
          widget.onTap?.call(id);
        }
      }
    }
    if (_pointers.isEmpty) {
      _primaryId = null;
      _dragging = false;
      _consumed = false;
      _secondaryButton = false;
    }
    _c.frame.value++;
  }

  void _onCancel(PointerCancelEvent e) {
    _closeMenu();
    _pointers.remove(e.pointer);
    _longPressTimer?.cancel();
    if (_pointers.isEmpty) {
      _primaryId = null;
      _dragging = false;
      _consumed = false;
      _secondaryButton = false;
    }
  }

  void _onHover(PointerHoverEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    _c.setHover(_c.pick(e.localPosition, _size));
  }

  void _onExit(PointerExitEvent e) => _c.setHover(-1);

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _c.camera.zoomBy(math.exp(-e.scrollDelta.dy * 0.0015));
      _c.frame.value++;
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _lastPanZoomScale = 1;
    _c.camera.grab();
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (_lastPanZoomScale > 0 && e.scale > 0) {
      _c.camera.zoomBy(e.scale / _lastPanZoomScale);
    }
    _lastPanZoomScale = e.scale;
    _c.camera.dragBy(e.panDelta.dx, e.panDelta.dy, _size);
    _c.frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        final view = MouseRegion(
          onExit: _onExit,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onCancel,
            onPointerHover: _onHover,
            onPointerSignal: _onSignal,
            onPointerPanZoomStart: _onPanZoomStart,
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _painter,
                size: Size.infinite,
              ),
            ),
          ),
        );
        return widget.interactive ? view : IgnorePointer(child: view);
      },
    );
  }
}
