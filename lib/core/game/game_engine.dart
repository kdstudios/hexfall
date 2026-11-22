import 'dart:typed_data';

import '../geometry/geodesic_grid.dart';
import 'game_config.dart';
import 'seeded_random.dart';

enum GameStatus { playing, won, lost }

/// Per-cell logical state codes (stored in a Uint8List).
class CellCode {
  const CellCode._();
  static const int hidden = 0;
  static const int revealed = 1;
  static const int flagged = 2;
  static const int exploded = 3; // the mine that ended the game
  static const int mineRevealed = 4; // a mine shown (shield hit / game over)
}

/// Result of one player action, used by the UI for animation and sound.
class RevealOutcome {
  const RevealOutcome({
    this.revealed = const [],
    this.depths = const [],
    this.mineHits = const [],
    this.shieldActivated = false,
    this.exploded = false,
    this.won = false,
  });

  static const RevealOutcome none = RevealOutcome();

  /// Safe cells newly revealed, in reveal order.
  final List<int> revealed;

  /// Flood-fill depth of each entry in [revealed] (for scan-wave timing).
  final List<int> depths;

  /// Mines the player stepped on during this action.
  final List<int> mineHits;
  final bool shieldActivated;
  final bool exploded;
  final bool won;

  bool get isEmpty => revealed.isEmpty && mineHits.isEmpty;
}

/// Pure Minesweeper rules on a geodesic grid. No rendering, no timers.
class GameEngine {
  GameEngine(GeodesicGrid grid, GameConfig config) : this._internal(grid, config, null);

  /// Test / restore helper with explicit mine positions.
  GameEngine.withMines(GeodesicGrid grid, GameConfig config, Set<int> mineCells)
      : this._internal(grid, config, mineCells);

  GameEngine._internal(this.grid, this.config, Set<int>? explicit)
      : state = Uint8List(grid.cellCount),
        mines = Uint8List(grid.cellCount),
        counts = Uint8List(grid.cellCount) {
    if (explicit != null) {
      for (final c in explicit) {
        mines[c] = 1;
      }
    } else {
      _placeMines();
    }
    mineCount = _countMines();
    _computeCounts();
  }

  /// Rebuilds an engine from [toJson]. Returns null if the data is not valid
  /// for [grid].
  static GameEngine? restore(GeodesicGrid grid, Map<String, Object?> j) {
    try {
      final config = GameConfig.fromJson((j['config'] as Map).cast<String, Object?>());
      final stateStr = j['state'] as String;
      final mineStr = j['mines'] as String;
      if (config.frequency != grid.frequency ||
          stateStr.length != grid.cellCount ||
          mineStr.length != grid.cellCount) {
        return null;
      }
      final mineCells = <int>{
        for (var i = 0; i < mineStr.length; i++)
          if (mineStr.codeUnitAt(i) == 0x31) i,
      };
      final e = GameEngine.withMines(grid, config, mineCells);
      for (var i = 0; i < stateStr.length; i++) {
        final code = stateStr.codeUnitAt(i) - 0x30;
        if (code < 0 || code > 4) return null;
        e.state[i] = code;
      }
      e.status = GameStatus.values[j['status'] as int];
      e.shieldAvailable = j['shield'] as bool;
      e.shieldUsed = j['shieldUsed'] as bool;
      e.explodedCell = j['exploded'] as int;
      e._recount();
      return e;
    } catch (_) {
      return null;
    }
  }

  final GeodesicGrid grid;
  final GameConfig config;

  /// 1 where a mine is.
  final Uint8List mines;

  /// Adjacent mine count for every cell.
  final Uint8List counts;

  /// [CellCode] per cell.
  final Uint8List state;

  late final int mineCount;

  GameStatus status = GameStatus.playing;
  bool shieldAvailable = true;
  bool shieldUsed = false;
  int explodedCell = -1;

  int revealedSafe = 0;
  int flagCount = 0;
  int _shownMines = 0; // mines revealed by the shield (not flagged)

  int get totalSafe => grid.cellCount - mineCount;
  double get percentCleared => totalSafe == 0 ? 100 : revealedSafe * 100.0 / totalSafe;
  int get minesRemaining => mineCount - flagCount - _shownMines;
  bool get isOver => status != GameStatus.playing;

  int get incorrectFlags {
    var n = 0;
    for (var i = 0; i < state.length; i++) {
      if (state[i] == CellCode.flagged && mines[i] == 0) n++;
    }
    return n;
  }

  // --- Setup -----------------------------------------------------------------

  void _placeMines() {
    final n = grid.cellCount;
    final want = (n * config.mineDensity).round().clamp(1, n - 13).toInt();
    final ids = List<int>.generate(n, (i) => i);
    final rnd = SeededRandom(config.seed);
    for (var i = 0; i < want; i++) {
      final j = i + rnd.nextInt(n - i);
      final t = ids[i];
      ids[i] = ids[j];
      ids[j] = t;
      mines[ids[i]] = 1;
    }
  }

  int _countMines() {
    var n = 0;
    for (final m in mines) {
      n += m;
    }
    return n;
  }

  void _computeCounts() {
    for (var c = 0; c < grid.cellCount; c++) {
      var n = 0;
      for (var k = grid.cellOffsets[c]; k < grid.cellOffsets[c + 1]; k++) {
        n += mines[grid.neighbourIndices[k]];
      }
      counts[c] = n;
    }
  }

  void _recount() {
    revealedSafe = 0;
    flagCount = 0;
    _shownMines = 0;
    for (var i = 0; i < state.length; i++) {
      final s = state[i];
      if (s == CellCode.revealed) revealedSafe++;
      if (s == CellCode.flagged) flagCount++;
      if (s == CellCode.mineRevealed && status == GameStatus.playing) _shownMines++;
    }
  }

  // --- Actions ---------------------------------------------------------------

  /// Reveal a hidden cell, or chord on a revealed number.
  RevealOutcome activate(int id) {
    if (isOver) return RevealOutcome.none;
    final s = state[id];
    if (s == CellCode.hidden) return _process([id]);
    if (s == CellCode.revealed && counts[id] > 0) return chord(id);
    return RevealOutcome.none;
  }

  RevealOutcome reveal(int id) {
    if (isOver || state[id] != CellCode.hidden) return RevealOutcome.none;
    return _process([id]);
  }

  /// Toggles a flag. Returns true if anything changed.
  bool toggleFlag(int id) {
    if (isOver) return false;
    final s = state[id];
    if (s == CellCode.hidden) {
      state[id] = CellCode.flagged;
      flagCount++;
      return true;
    }
    if (s == CellCode.flagged) {
      state[id] = CellCode.hidden;
      flagCount--;
      return true;
    }
    return false;
  }

  /// Traditional chord: if adjacent flags == number, reveal the other
  /// neighbours. Wrong flags still lead to mines being hit.
  RevealOutcome chord(int id) {
    if (isOver || state[id] != CellCode.revealed || counts[id] == 0) {
      return RevealOutcome.none;
    }
    var flags = 0;
    final targets = <int>[];
    for (var k = grid.cellOffsets[id]; k < grid.cellOffsets[id + 1]; k++) {
      final nb = grid.neighbourIndices[k];
      if (state[nb] == CellCode.flagged) {
        flags++;
      } else if (state[nb] == CellCode.hidden) {
        targets.add(nb);
      }
    }
    if (flags != counts[id] || targets.isEmpty) return RevealOutcome.none;
    return _process(targets);
  }

  RevealOutcome _process(List<int> targets) {
    final revealed = <int>[];
    final depths = <int>[];
    final hits = <int>[];
    var shield = false;
    var exploded = false;

    for (final t in targets) {
      if (isOver) break;
      if (state[t] != CellCode.hidden) continue;
      if (mines[t] == 1) {
        hits.add(t);
        if (shieldAvailable) {
          shieldAvailable = false;
          shieldUsed = true;
          shield = true;
          state[t] = CellCode.mineRevealed;
          _shownMines++;
        } else {
          state[t] = CellCode.exploded;
          explodedCell = t;
          status = GameStatus.lost;
          exploded = true;
          _revealAllMines();
        }
      } else {
        _flood(t, revealed, depths);
      }
    }
    var won = false;
    if (status == GameStatus.playing && revealedSafe >= totalSafe) {
      status = GameStatus.won;
      won = true;
    }
    return RevealOutcome(
      revealed: revealed,
      depths: depths,
      mineHits: hits,
      shieldActivated: shield,
      exploded: exploded,
      won: won,
    );
  }

  void _flood(int start, List<int> out, List<int> depths) {
    state[start] = CellCode.revealed;
    revealedSafe++;
    out.add(start);
    depths.add(0);
    if (counts[start] != 0) return;

    // Breadth-first; each cell is marked revealed when queued so it is never
    // processed twice. Flagged cells are left alone.
    final queue = <int>[start];
    final qDepth = <int>[0];
    var head = 0;
    while (head < queue.length) {
      final c = queue[head];
      final d = qDepth[head];
      head++;
      if (counts[c] != 0) continue;
      for (var k = grid.cellOffsets[c]; k < grid.cellOffsets[c + 1]; k++) {
        final nb = grid.neighbourIndices[k];
        if (state[nb] != CellCode.hidden) continue;
        state[nb] = CellCode.revealed;
        revealedSafe++;
        out.add(nb);
        depths.add(d + 1);
        queue.add(nb);
        qDepth.add(d + 1);
      }
    }
  }

  void _revealAllMines() {
    for (var i = 0; i < mines.length; i++) {
      if (mines[i] == 1 && state[i] == CellCode.hidden) {
        state[i] = CellCode.mineRevealed;
      }
    }
  }

  // --- Persistence -----------------------------------------------------------

  Map<String, Object?> toJson() => {
        'config': config.toJson(),
        'state': String.fromCharCodes([for (final s in state) 0x30 + s]),
        'mines': String.fromCharCodes([for (final m in mines) 0x30 + m]),
        'status': status.index,
        'shield': shieldAvailable,
        'shieldUsed': shieldUsed,
        'exploded': explodedCell,
      };
}
