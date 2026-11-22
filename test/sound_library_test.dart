import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexfall/persistence/key_value_store.dart';
import 'package:hexfall/services/sound_library.dart';
import 'package:hexfall/services/zip_writer.dart';

Uint8List fakeWav([int size = 200]) {
  final b = Uint8List(size);
  b.setAll(0, ascii.encode('RIFF'));
  b.setAll(8, ascii.encode('WAVE'));
  return b;
}

Uint8List fakeMp3([int size = 200]) {
  final b = Uint8List(size);
  b.setAll(0, ascii.encode('ID3'));
  return b;
}

void main() {
  test('CRC-32 matches the standard check value', () {
    expect(ZipWriter.crc32(Uint8List.fromList(ascii.encode('123456789'))), 0xCBF43926);
  });

  test('zip output has valid structure', () {
    final zip = ZipWriter.build({'a.wav': fakeWav(100), 'b.mp3': fakeMp3(80)});
    final bd = ByteData.sublistView(zip);
    expect(bd.getUint32(0, Endian.little), 0x04034b50); // first local header
    // End-of-central-directory record is the last 22 bytes.
    final eocd = zip.length - 22;
    expect(bd.getUint32(eocd, Endian.little), 0x06054b50);
    expect(bd.getUint16(eocd + 10, Endian.little), 2); // entries
    final cdOffset = bd.getUint32(eocd + 16, Endian.little);
    expect(bd.getUint32(cdOffset, Endian.little), 0x02014b50);
  });

  test('custom sounds persist across restarts', () async {
    final store = MemoryStore();
    final lib = await SoundLibrary.load(store);
    expect(await lib.setCustom(SoundSlot.explosion, fakeWav(), 'wav'), isNull);
    final again = await SoundLibrary.load(store);
    expect(again.isCustom(SoundSlot.explosion), isTrue);
    expect(again.custom(SoundSlot.explosion)!.bytes.length, 200);
    await again.reset(SoundSlot.explosion);
    expect((await SoundLibrary.load(store)).isCustom(SoundSlot.explosion), isFalse);
  });

  test('rejects wrong types, fake files and oversize files', () async {
    final lib = await SoundLibrary.load(MemoryStore());
    expect(await lib.setCustom(SoundSlot.click, fakeWav(), 'ogg'), isNotNull);
    expect(await lib.setCustom(SoundSlot.click, Uint8List(500), 'wav'), isNotNull);
    expect(await lib.setCustom(SoundSlot.click, fakeMp3(), 'wav'), isNotNull);
    expect(await lib.setCustom(SoundSlot.click, fakeWav(SoundLibrary.maxFileBytes + 1), 'wav'), isNotNull);
    expect(lib.isCustom(SoundSlot.click), isFalse);
    expect(await lib.setCustom(SoundSlot.click, fakeMp3(), 'MP3'), isNull);
  });

  test('total custom size is capped', () async {
    final lib = await SoundLibrary.load(MemoryStore());
    final big = fakeWav(2000 * 1024);
    expect(await lib.setCustom(SoundSlot.music, big, 'wav'), isNull);
    expect(await lib.setCustom(SoundSlot.ambient, big, 'wav'), isNotNull);
    // Replacing the same slot does not double count.
    expect(await lib.setCustom(SoundSlot.music, fakeWav(2200 * 1024), 'wav'), isNull);
  });

  test('bulk import matches files to sounds by name', () async {
    final lib = await SoundLibrary.load(MemoryStore());
    final report = await lib.importFiles([
      ('Explosion.WAV', fakeWav()),
      ('music.mp3', fakeMp3()),
      ('random.wav', fakeWav()),
    ]);
    expect(lib.isCustom(SoundSlot.explosion), isTrue);
    expect(lib.custom(SoundSlot.music)!.ext, 'mp3');
    expect(report.where((l) => l.contains('skipped')).length, 1);
  });

  test('corrupt stored sound is ignored', () async {
    final store = MemoryStore()..data['hexfall.sound.flag'] = '{nope';
    final lib = await SoundLibrary.load(store);
    expect(lib.isCustom(SoundSlot.flag), isFalse);
  });
}
