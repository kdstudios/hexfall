import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/core/game/game_config.dart';
import 'package:hexfall/core/game/game_engine.dart';
import 'package:hexfall/core/game/medals.dart';
import 'package:hexfall/core/game/seeded_random.dart';
import 'package:hexfall/core/geometry/geodesic_grid.dart';
import 'package:hexfall/core/planet/planet_environment.dart';

GameConfig cfg({int f = 4, double d = 0.10, int seed = 1}) => GameConfig(
      frequency: f,
      mineDensity: d,
      seed: seed,
      environment: PlanetEnvironment.oceanic,
    );

void main() {
  final grid = GeodesicGrid.generate(4);

  group('mine generation', () {
    test('mine count follows density and is stable per seed', () {
      final a = GameEngine(grid, cfg(seed: 77));
      final b = GameEngine(grid, cfg(seed: 77));
      final c = GameEngine(grid, cfg(seed: 78));
      expect(a.mineCount, (162 * 0.10).round());
      expect(a.mines, b.mines);
      expect(a.mines, isNot(c.mines));
    });

    test('numbers equal adjacent mine counts', () {
      final e = GameEngine(grid, cfg(seed: 5));
      for (var c = 0; c < grid.cellCount; c++) {
        var n = 0;
        for (final nb in grid.cells[c].neighbours) {
          n += e.mines[nb];
        }
        expect(e.counts[c], n);
      }
    });

    test('pentagons count five neighbours, hexagons six', () {
      final e = GameEngine.withMines(grid, cfg(), grid.cells.where((c) => c.isPentagon).map((c) => c.id).toSet());
      // Every hexagon touching a pentagon sees at most its 6 neighbours.
      for (final cell in grid.cells) {
        expect(e.counts[cell.id], lessThanOrEqualTo(cell.sides));
      }
    });

    test('PRNG is deterministic across runs', () {
      final a = SeededRandom(123456);
      final b = SeededRandom(123456);
      expect([for (var i = 0; i < 10; i++) a.nextUint32()], [for (var i = 0; i < 10; i++) b.nextUint32()]);
    });

    test('first click is not protected (a mine can be hit immediately)', () {
      final e = GameEngine(grid, cfg(seed: 9));
      final mine = e.mines.indexOf(1);
      final out = e.activate(mine);
      expect(out.mineHits, [mine]);
      expect(out.shieldActivated, isTrue);
    });
  });

  group('reveal & flood fill', () {
    test('revealing a number reveals only that cell', () {
      final e = GameEngine(grid, cfg(seed: 3));
      final c = List.generate(grid.cellCount, (i) => i).firstWhere((i) => e.mines[i] == 0 && e.counts[i] > 0);
      final out = e.reveal(c);
      expect(out.revealed, [c]);
      expect(e.revealedSafe, 1);
    });

    test('zero cell floods through connected zeros and their border numbers', () {
      // One mine far from the cell we click.
      final e = GameEngine.withMines(grid, cfg(), {0});
      final start = grid.cells[0].neighbours.length; // arbitrary safe cell
      final safe = List.generate(grid.cellCount, (i) => i)
          .firstWhere((i) => e.counts[i] == 0 && i != 0 && !grid.cells[0].neighbours.contains(i));
      final out = e.reveal(safe);
      expect(start, isNonZero);
      expect(out.revealed.length, e.totalSafe, reason: 'single mine: everything safe is connected');
      expect(out.revealed.toSet().length, out.revealed.length, reason: 'no duplicates');
      expect(e.status, GameStatus.won);
      expect(out.won, isTrue);
      expect(e.state[0], CellCode.hidden);
    });

    test('flood does not reveal flagged cells', () {
      final e = GameEngine.withMines(grid, cfg(), {0});
      final target = grid.cells[5].neighbours.first;
      e.toggleFlag(target);
      final safe = List.generate(grid.cellCount, (i) => i)
          .firstWhere((i) => e.counts[i] == 0 && i != 0 && i != target && !grid.cells[0].neighbours.contains(i));
      e.reveal(safe);
      expect(e.state[target], CellCode.flagged);
    });

    test('revealed cells cannot be revealed or flagged again', () {
      final e = GameEngine.withMines(grid, cfg(), {0});
      final c = grid.cells[0].neighbours.first; // a number next to the mine
      e.reveal(c);
      expect(e.reveal(c).isEmpty, isTrue);
      expect(e.toggleFlag(c), isFalse);
    });

    test('flagged cells cannot be revealed', () {
      final e = GameEngine.withMines(grid, cfg(), {0});
      e.toggleFlag(0);
      expect(e.reveal(0).isEmpty, isTrue);
      expect(e.state[0], CellCode.flagged);
      expect(e.toggleFlag(0), isTrue);
      expect(e.state[0], CellCode.hidden);
    });
  });

  group('shield and game over', () {
    test('first mine consumes the shield, second ends the game', () {
      final e = GameEngine.withMines(grid, cfg(), {0, 50});
      final first = e.reveal(0);
      expect(first.shieldActivated, isTrue);
      expect(e.status, GameStatus.playing);
      expect(e.shieldAvailable, isFalse);
      expect(e.shieldUsed, isTrue);
      expect(e.state[0], CellCode.mineRevealed);
      expect(e.minesRemaining, 1);

      final second = e.reveal(50);
      expect(second.exploded, isTrue);
      expect(e.status, GameStatus.lost);
      expect(e.state[50], CellCode.exploded);
      expect(e.explodedCell, 50);
    });

    test('game over reveals every mine and keeps incorrect flags visible', () {
      final e = GameEngine.withMines(grid, cfg(), {0, 50, 70});
      e.reveal(0);
      e.toggleFlag(70); // correct flag
      final wrong = grid.cells[100].id;
      e.toggleFlag(wrong); // wrong flag
      e.reveal(50);
      expect(e.state[70], CellCode.flagged);
      expect(e.state[wrong], CellCode.flagged);
      expect(e.incorrectFlags, 1);
      for (final m in [0, 50]) {
        expect(e.state[m] == CellCode.mineRevealed || e.state[m] == CellCode.exploded, isTrue);
      }
    });

    test('no actions after game over', () {
      final e = GameEngine.withMines(grid, cfg(), {0, 1});
      e.reveal(0);
      e.reveal(1);
      expect(e.isOver, isTrue);
      expect(e.reveal(10).isEmpty, isTrue);
      expect(e.toggleFlag(10), isFalse);
    });
  });

  group('chording', () {
    test('chord reveals remaining neighbours when flags match', () {
      final mine = grid.cells[20].neighbours.first;
      final e = GameEngine.withMines(grid, cfg(), {mine});
      e.reveal(20);
      expect(e.counts[20], 1);
      e.toggleFlag(mine);
      final out = e.chord(20);
      expect(out.revealed, isNotEmpty);
      for (final nb in grid.cells[20].neighbours) {
        if (nb != mine) expect(e.state[nb], CellCode.revealed);
      }
    });

    test('chord does nothing when flag count differs', () {
      final mine = grid.cells[20].neighbours.first;
      final e = GameEngine.withMines(grid, cfg(), {mine});
      e.reveal(20);
      expect(e.chord(20).isEmpty, isTrue);
    });

    test('chord with a wrong flag hits the real mine (uses shield first)', () {
      final mine = grid.cells[20].neighbours.first;
      final wrong = grid.cells[20].neighbours.last;
      final e = GameEngine.withMines(grid, cfg(), {mine});
      e.reveal(20);
      e.toggleFlag(wrong);
      final out = e.chord(20);
      expect(out.mineHits, [mine]);
      expect(out.shieldActivated, isTrue);
    });

    test('activate on a revealed number chords', () {
      final mine = grid.cells[20].neighbours.first;
      final e = GameEngine.withMines(grid, cfg(), {mine});
      e.reveal(20);
      e.toggleFlag(mine);
      expect(e.activate(20).revealed, isNotEmpty);
    });
  });

  group('winning', () {
    test('win requires every safe cell, not flags', () {
      final e = GameEngine.withMines(grid, cfg(), {0});
      e.toggleFlag(100); // incorrect flag must not block victory
      e.reveal(100 == 0 ? 1 : 101);
      for (var i = 1; i < grid.cellCount; i++) {
        if (e.state[i] == CellCode.hidden) e.reveal(i);
      }
      // cell 100 is flagged and safe, so one safe cell remains.
      expect(e.status, GameStatus.playing);
      e.toggleFlag(100);
      e.reveal(100);
      expect(e.status, GameStatus.won);
      expect(e.percentCleared, 100);
    });

    test('medal rules', () {
      final c = cfg();
      expect(MedalRules.evaluate(won: false, shieldUsed: false, incorrectFlags: 0, elapsedMs: 1, config: c), Medal.none);
      expect(MedalRules.evaluate(won: true, shieldUsed: true, incorrectFlags: 0, elapsedMs: 1, config: c), Medal.bronze);
      expect(MedalRules.evaluate(won: true, shieldUsed: false, incorrectFlags: 1, elapsedMs: 1, config: c), Medal.silver);
      expect(
        MedalRules.evaluate(
            won: true, shieldUsed: false, incorrectFlags: 0, elapsedMs: MedalRules.goldTimeTargetMs(c) + 1, config: c),
        Medal.silver,
      );
      expect(MedalRules.evaluate(won: true, shieldUsed: false, incorrectFlags: 0, elapsedMs: 1000, config: c), Medal.gold);
    });
  });

  group('serialisation', () {
    test('engine state round-trips exactly', () {
      final e = GameEngine(grid, cfg(seed: 21));
      final safe = List.generate(grid.cellCount, (i) => i).firstWhere((i) => e.mines[i] == 0 && e.counts[i] == 0);
      e.reveal(safe);
      final mine = e.mines.indexOf(1);
      e.toggleFlag(mine);
      final restored = GameEngine.restore(grid, e.toJson())!;
      expect(restored.state, e.state);
      expect(restored.mines, e.mines);
      expect(restored.counts, e.counts);
      expect(restored.revealedSafe, e.revealedSafe);
      expect(restored.flagCount, e.flagCount);
      expect(restored.shieldAvailable, e.shieldAvailable);
      expect(restored.status, e.status);
    });

    test('shield state survives a round trip', () {
      final e = GameEngine.withMines(grid, cfg(), {0, 50});
      e.reveal(0);
      final r = GameEngine.restore(grid, e.toJson())!;
      expect(r.shieldAvailable, isFalse);
      expect(r.shieldUsed, isTrue);
      expect(r.minesRemaining, e.minesRemaining);
    });

    test('mismatched saves are rejected', () {
      final e = GameEngine(grid, cfg());
      final other = GeodesicGrid.generate(3);
      expect(GameEngine.restore(other, e.toJson()), isNull);
      expect(GameEngine.restore(grid, {'bad': 1}), isNull);
    });
  });
}
