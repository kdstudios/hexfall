import 'package:audioplayers/audioplayers.dart';

import '../persistence/models.dart';
import 'sound_library.dart';

enum Sfx { reveal, scan, flag, unflag, shield, explosion, victory, defeat, click }

/// Audio facade. The game only talks to this interface; tests and platforms
/// where audio fails use [SilentAudio].
abstract class AudioService {
  void play(Sfx sfx);

  /// Starts music + ambience (browsers only allow this after a user gesture,
  /// so call it from a button press).
  void ensureStarted();
  void applySettings(Settings s);

  /// Plays a slot once for the sound library screen (replaces any preview).
  void preview(SoundSlot slot);
  void stopPreview();
  void dispose();
}

class SilentAudio implements AudioService {
  @override
  void preview(SoundSlot slot) {}
  @override
  void stopPreview() {}
  @override
  void play(Sfx sfx) {}
  @override
  void ensureStarted() {}
  @override
  void applySettings(Settings s) {}
  @override
  void dispose() {}
}

/// audioplayers based implementation. Every call is wrapped so an audio
/// failure (unsupported device, blocked autoplay) can never break gameplay.
class PlayersAudio implements AudioService {
  PlayersAudio(this.library) {
    library.addListener(_onLibraryChanged);
    _preview = AudioPlayer();
    _music = AudioPlayer();
    _ambient = AudioPlayer();
    for (final s in Sfx.values) {
      _sfx[s] = AudioPlayer();
    }
  }

  final SoundLibrary library;
  late final AudioPlayer _preview;
  late final AudioPlayer _music;
  late final AudioPlayer _ambient;
  final Map<Sfx, AudioPlayer> _sfx = {};
  Settings _settings = const Settings();
  bool _started = false;


  Source _source(SoundSlot slot) {
    final c = library.custom(slot);
    if (c != null) return BytesSource(c.bytes, mimeType: c.mime);
    return AssetSource('audio/${slot.name}.wav');
  }

  /// Plays [slot]; if a user file fails to play, falls back to the default.
  Future<void> _playSlot(AudioPlayer p, SoundSlot slot, double volume) async {
    try {
      await p.play(_source(slot), volume: volume);
    } catch (_) {
      if (library.isCustom(slot)) {
        await p.play(AssetSource('audio/${slot.name}.wav'), volume: volume);
      }
    }
  }

  void _onLibraryChanged() {
    if (!_started) return;
    // Restart the loops so replaced music / ambience is heard immediately.
    _guard(() async {
      await _music.stop();
      await _ambient.stop();
      await _playSlot(_music, SoundSlot.music, _master * _settings.musicVolume);
      await _playSlot(_ambient, SoundSlot.ambient, _master * _settings.ambientVolume);
    });
  }

  @override
  void preview(SoundSlot slot) {
    final vol = _master * (slot.loops ? _settings.musicVolume : _settings.sfxVolume);
    _guard(() async {
      await _preview.stop();
      await _playSlot(_preview, slot, vol <= 0 ? 0.8 : vol);
    });
  }

  @override
  void stopPreview() => _guard(() => _preview.stop());

  double get _master => _settings.muted ? 0.0 : _settings.masterVolume;

  @override
  void play(Sfx sfx) {
    final v = _master * _settings.sfxVolume;
    if (v <= 0) return;
    _guard(() async {
      final p = _sfx[sfx]!;
      await p.stop();
      await _playSlot(p, SoundSlot.values.byName(sfx.name), v);
    });
  }

  @override
  void ensureStarted() {
    if (_started) return;
    _started = true;
    _guard(() async {
      await _music.setReleaseMode(ReleaseMode.loop);
      await _ambient.setReleaseMode(ReleaseMode.loop);
      await _playSlot(_music, SoundSlot.music, _master * _settings.musicVolume);
      await _playSlot(_ambient, SoundSlot.ambient, _master * _settings.ambientVolume);
    });
  }

  @override
  void applySettings(Settings s) {
    _settings = s;
    _guard(() async {
      await _music.setVolume(_master * s.musicVolume);
      await _ambient.setVolume(_master * s.ambientVolume);
    });
  }

  void _guard(Future<void> Function() fn) {
    fn().catchError((Object _) {});
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    _guard(() async {
      await _preview.dispose();
      await _music.dispose();
      await _ambient.dispose();
      for (final p in _sfx.values) {
        await p.dispose();
      }
    });
  }
}
