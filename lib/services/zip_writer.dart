import 'dart:convert';
import 'dart:typed_data';

/// Minimal ZIP writer (stored / no compression) used to export all sounds as
/// one file without an extra dependency. Output opens in any unzip tool.
class ZipWriter {
  const ZipWriter._();

  static final List<int> _table = _makeTable();

  static List<int> _makeTable() {
    final t = List<int>.filled(256, 0);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? ((0xEDB88320 ^ (c ~/ 2)) & 0xFFFFFFFF) : c ~/ 2;
      }
      t[n] = c;
    }
    return t;
  }

  /// CRC-32 (IEEE). Written with ~/ instead of >> so it is identical on the web.
  static int crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = (_table[(crc ^ b) & 0xFF] ^ (crc ~/ 256)) & 0xFFFFFFFF;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static Uint8List build(Map<String, Uint8List> files) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var count = 0;
    // DOS date 2026-01-01 00:00:00.
    const dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;
    const dosTime = 0;

    void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v ~/ 256) & 0xFF]);
    void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v ~/ 256) & 0xFF, (v ~/ 65536) & 0xFF, (v ~/ 16777216) & 0xFF]);

    files.forEach((name, data) {
      final nameBytes = utf8.encode(name);
      final crc = crc32(data);
      final offset = out.length;

      u32(out, 0x04034b50);
      u16(out, 20); // version needed
      u16(out, 0x0800); // flags: UTF-8 names
      u16(out, 0); // method: stored
      u16(out, dosTime);
      u16(out, dosDate);
      u32(out, crc);
      u32(out, data.length);
      u32(out, data.length);
      u16(out, nameBytes.length);
      u16(out, 0);
      out.add(nameBytes);
      out.add(data);

      u32(central, 0x02014b50);
      u16(central, 20); // made by
      u16(central, 20); // needed
      u16(central, 0x0800);
      u16(central, 0);
      u16(central, dosTime);
      u16(central, dosDate);
      u32(central, crc);
      u32(central, data.length);
      u32(central, data.length);
      u16(central, nameBytes.length);
      u16(central, 0); // extra
      u16(central, 0); // comment
      u16(central, 0); // disk
      u16(central, 0); // internal attrs
      u32(central, 0); // external attrs
      u32(central, offset);
      central.add(nameBytes);
      count++;
    });

    final cdOffset = out.length;
    final cd = central.toBytes();
    out.add(cd);
    u32(out, 0x06054b50);
    u16(out, 0);
    u16(out, 0);
    u16(out, count);
    u16(out, count);
    u32(out, cd.length);
    u32(out, cdOffset);
    u16(out, 0);
    return out.toBytes();
  }
}
