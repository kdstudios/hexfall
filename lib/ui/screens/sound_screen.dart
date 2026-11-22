import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/sound_library.dart';
import '../../theme/hexfall_theme.dart';
import '../widgets/sci_fi.dart';

/// Export the game's current sounds and replace any of them with your own
/// .wav / .mp3 files.
class SoundLibraryScreen extends StatefulWidget {
  const SoundLibraryScreen({super.key});

  @override
  State<SoundLibraryScreen> createState() => _SoundLibraryScreenState();
}

class _SoundLibraryScreenState extends State<SoundLibraryScreen> {
  bool _busy = false;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));
  }

  Future<List<(String, Uint8List)>> _pick({required bool multiple}) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: multiple,
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3'],
      withData: true,
    );
    if (res == null) return [];
    return [
      for (final f in res.files)
        if (f.bytes != null) (f.name, f.bytes!),
    ];
  }

  Future<void> _save(String name, Uint8List bytes) async {
    final ext = name.contains('.') ? name.split('.').last : 'wav';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export sound',
      fileName: name,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: [ext],
    );
    // Desktop builds return a path and expect the app to write the file.
    final desktop = {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(defaultTargetPlatform);
    if (!kIsWeb && desktop && path != null) {
      await File(path).writeAsBytes(bytes);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _say('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final lib = services.sounds;
    return MenuScreen(
      title: 'Sound Library',
      child: ListenableBuilder(
        listenable: lib,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SciFiPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Export the sounds currently in use, edit or replace them, and import your own.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tip: name files after the sound (for example explosion.mp3 or music.wav) and use '
                      '"Import files" to replace several at once. Supported: .wav and .mp3, up to '
                      '${SoundLibrary.maxFileBytes ~/ 1024} KB each and ${SoundLibrary.maxTotalBytes ~/ 1024} KB in total. '
                      'Custom sounds are stored on this device.',
                      style: const TextStyle(fontSize: 11, color: HexfallTheme.textDim),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SciFiButton(
                          label: 'Export all (.zip)',
                          icon: Icons.archive,
                          dense: true,
                          primary: true,
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final bytes = await lib.exportAllZip();
                                    await _save('hexfall_sounds.zip', bytes);
                                    _say('Exported all sounds.');
                                  }),
                        ),
                        SciFiButton(
                          label: 'Import files',
                          icon: Icons.upload_file,
                          dense: true,
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                    final files = await _pick(multiple: true);
                                    if (files.isEmpty) return;
                                    final report = await lib.importFiles(files);
                                    _say(report.join('\n'));
                                  }),
                        ),
                        SciFiButton(
                          label: 'Reset all',
                          icon: Icons.restore,
                          dense: true,
                          onPressed: _busy || lib.totalCustomBytes == 0
                              ? null
                              : () => _run(() async {
                                    await lib.resetAll();
                                    _say('All sounds restored to defaults.');
                                  }),
                        ),
                      ],
                    ),
                    if (lib.totalCustomBytes > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Custom sounds use ${(lib.totalCustomBytes / 1024).round()} KB of '
                          '${SoundLibrary.maxTotalBytes ~/ 1024} KB.',
                          style: const TextStyle(fontSize: 11, color: HexfallTheme.cyanSoft),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final slot in SoundSlot.values) _row(context, services, lib, slot),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Services services, SoundLibrary lib, SoundSlot slot) {
    final c = lib.custom(slot);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SciFiPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        border: c != null ? HexfallTheme.amber : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    c == null ? 'Default (${slot.name}.wav)' : 'Custom · .${c.ext} · ${(c.bytes.length / 1024).round()} KB',
                    style: TextStyle(fontSize: 11, color: c == null ? HexfallTheme.textDim : HexfallTheme.amber),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Play',
              icon: const Icon(Icons.play_arrow, color: HexfallTheme.cyan),
              onPressed: () => services.audio.preview(slot),
            ),
            IconButton(
              tooltip: 'Export this sound',
              icon: const Icon(Icons.download, color: HexfallTheme.cyanSoft),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final (name, bytes) = await lib.exportSlot(slot);
                        await _save(name, bytes);
                        _say('Exported $name.');
                      }),
            ),
            IconButton(
              tooltip: 'Replace with your own file',
              icon: const Icon(Icons.upload, color: HexfallTheme.cyanSoft),
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final files = await _pick(multiple: false);
                        if (files.isEmpty) return;
                        final (name, bytes) = files.first;
                        final ext = name.contains('.') ? name.split('.').last : '';
                        final err = await lib.setCustom(slot, bytes, ext);
                        _say(err ?? '${slot.label} replaced.');
                      }),
            ),
            IconButton(
              tooltip: 'Restore default',
              icon: Icon(Icons.restore, color: c == null ? HexfallTheme.textDim : HexfallTheme.amber),
              onPressed: c == null ? null : () => _run(() => lib.reset(slot)),
            ),
          ],
        ),
      ),
    );
  }
}
