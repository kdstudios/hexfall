/// Small deterministic PRNG (xorshift32) that produces identical sequences on
/// the Dart VM and in JavaScript (Flutter web).
///
/// Rules that keep it web-safe: every value is kept as an unsigned 32-bit int,
/// every product stays below 2^53, and we use `~/` instead of `>>` on values
/// that may exceed 2^31.
class SeededRandom {
  SeededRandom(int seed) : _s = _scramble(seed) {
    if (_s == 0) _s = 0x9E3779B9;
  }

  int _s;

  static int _scramble(int seed) {
    var h = seed & 0xFFFFFFFF;
    h = (h ^ (h ~/ 65536)) & 0xFFFFFFFF;
    h = (h * 40503) & 0xFFFFFFFF;
    h = (h ^ (h ~/ 8192)) & 0xFFFFFFFF;
    h = (h * 40503) & 0xFFFFFFFF;
    h = (h ^ (h ~/ 65536)) & 0xFFFFFFFF;
    return h;
  }

  int nextUint32() {
    var x = _s;
    x = (x ^ ((x * 8192) & 0xFFFFFFFF)) & 0xFFFFFFFF; // x ^= x << 13
    x = (x ^ (x ~/ 131072)) & 0xFFFFFFFF; // x ^= x >> 17
    x = (x ^ ((x * 32) & 0xFFFFFFFF)) & 0xFFFFFFFF; // x ^= x << 5
    _s = x;
    return x;
  }

  /// Uniform-ish integer in [0, max).
  int nextInt(int max) => nextUint32() % max;

  /// Double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Stable string hash (web-safe) used for seeds such as the daily planet.
  static int hashString(String s) {
    var h = 5381;
    for (final unit in s.codeUnits) {
      h = ((h * 33) ^ unit) & 0xFFFFFFFF;
    }
    return h;
  }
}
