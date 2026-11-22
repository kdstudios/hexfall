import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../persistence/key_value_store.dart';
import 'zip_writer.dart';

/// Every replaceable sound. Names match the default asset file names.
enum SoundSlot { reveal, scan, flag, unflag, shield, explosion, victory, defeat, click, music, ambient }

extension SoundSlotInfo on SoundSlot {
  String get label => switch (this) {
        SoundSlot.reveal => 'Tile reveal',
        SoundSlot.scan => 'Scanning wave',
        SoundSlot.flag => 'Flag placed',
        SoundSlot.unflag => 'Flag removed',
        SoundSlot.shield => 'Shield activation',
        SoundSlot.explosion => 'Mine explosion',
        SoundSlot.victory => 'Victory',
        SoundSlot.defeat => 'Defeat',
        SoundSlot.click => 'Menu click',
        SoundSlot.music => 'Background music (loops)',
        SoundSlot.ambient => 'Planet ambience (loops)',
      };

  bool get loops => this == SoundSlot.music || this == SoundSlot.ambient;
  String get defaultAsset => 'assets/audio/$name.wav';
}

class CustomSound {
  const CustomSound(this.bytes, this.ext);
  final Uint8List bytes;
  final String ext; // 'wav' or 'mp3'

  String get mime => ext == 'mp3' ? 'audio/mpeg' : 'audio/wav';
}

/// The player's sound set: built-in defaults plus optional user replacements,
/// stored on-device (one key per sound) so they survive restarts on every
/// platform, including the web.
class SoundLibrary extends ChangeNotifier {
  SoundLibrary(this._store);

  final KeyValueStore _store;
  final Map<SoundSlot, CustomSound> _custom = {};

  static const int maxFileBytes = 2500 * 1024;
  static const int maxTotalBytes = 3500 * 1024;

  static String _key(SoundSlot s) => 'hexfall.sound.${s.name}';

  static Future<SoundLibrary> load(KeyValueStore store) async {
    final lib = SoundLibrary(store);
    for (final slot in SoundSlot.values) {
      try {
        final raw = await store.read(_key(slot));
        if (raw == null) continue;
        final j = (jsonDecode(raw) as Map).cast<String, Object?>();
        lib._custom[slot] = CustomSound(base64Decode(j['b64'] as String), j['ext'] as String);
      } catch (_) {
        // Ignore unreadable entries: the default sound is used instead.
      }
    }
    return lib;
  }

  CustomSound? custom(SoundSlot slot) => _custom[slot];
  bool isCustom(SoundSlot slot) => _custom.containsKey(slot);
  int get totalCustomBytes => _custom.values.fold(0, (n, c) => n + c.bytes.length);

  /// Checks that [bytes] really look like WAV or MP3 data.
  static String? validate(Uint8List bytes, String ext) {
    final e = ext.toLowerCase();
    if (e != 'wav' && e != 'mp3') return 'Only .wav and .mp3 files are supported.';
    if (bytes.length < 64) return 'That file is too small to be audio.';
    if (bytes.length > maxFileBytes) {
      return 'File is too large (max ${maxFileBytes ~/ 1024} KB). Try a shorter or lower-bitrate file.';
    }
    if (e == 'wav') {
      final ok = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && // RIFF
          bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45; // WAVE
      if (!ok) return 'That does not look like a valid .wav file.';
    } else {
      final id3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
      final frame = bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      if (!id3 && !frame) return 'That does not look like a valid .mp3 file.';
    }
    return null;
  }

  /// Replaces [slot]. Returns an error message, or null on success.
  Future<String?> setCustom(SoundSlot slot, Uint8List bytes, String ext) async {
    final e = ext.toLowerCase();
    final problem = validate(bytes, e);
    if (problem != null) return problem;
    final others = totalCustomBytes - (_custom[slot]?.bytes.length ?? 0);
    if (others + bytes.length > maxTotalBytes) {
      return 'Custom sounds are limited to ${maxTotalBytes ~/ 1024} KB in total on this device. Reset or shrink another sound first.';
    }
    try {
      await _store.write(_key(slot), jsonEncode({'ext': e, 'b64': base64Encode(bytes)}));
    } catch (_) {
      return 'Could not save the sound (device or browser storage is full).';
    }
    _custom[slot] = CustomSound(bytes, e);
    notifyListeners();
    return null;
  }

  Future<void> reset(SoundSlot slot) async {
    _custom.remove(slot);
    await _store.remove(_key(slot));
    notifyListeners();
  }

  Future<void> resetAll() async {
    for (final slot in SoundSlot.values) {
      _custom.remove(slot);
      await _store.remove(_key(slot));
    }
    notifyListeners();
  }

  /// Bytes + file name of the sound currently in use for [slot].
  Future<(String, Uint8List)> exportSlot(SoundSlot slot) async {
    final c = _custom[slot];
    if (c != null) return ('${slot.name}.${c.ext}', c.bytes);
    final data = await rootBundle.load(slot.defaultAsset);
    return ('${slot.name}.wav', data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  /// All 11 sounds currently in use, as one .zip.
  Future<Uint8List> exportAllZip() async {
    final files = <String, Uint8List>{};
    for (final slot in SoundSlot.values) {
      final (name, bytes) = await exportSlot(slot);
      files[name] = bytes;
    }
    return ZipWriter.build(files);
  }

  /// Assigns each picked file to the slot matching its file name
  /// (e.g. `explosion.mp3` -> Mine explosion). Returns one report line per file.
  Future<List<String>> importFiles(List<(String, Uint8List)> files) async {
    final report = <String>[];
    for (final (name, bytes) in files) {
      final dot = name.lastIndexOf('.');
      final base = (dot < 0 ? name : name.substring(0, dot)).toLowerCase().trim();
      final ext = dot < 0 ? '' : name.substring(dot + 1);
      SoundSlot? slot;
      for (final s in SoundSlot.values) {
        if (s.name == base) slot = s;
      }
      if (slot == null) {
        report.add('$name: skipped (file name must match a sound, e.g. "${SoundSlot.reveal.name}.wav")');
        continue;
      }
      final err = await setCustom(slot, bytes, ext);
      report.add(err == null ? '$name: imported as "${slot.label}"' : '$name: $err');
    }
    return report;
  }
}
