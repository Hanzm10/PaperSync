import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/usb/hid_descriptor.dart';

Uint8List _hex(String hex) {
  final clean = hex.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// A descriptor laid out like the T605's Report ID 9: three pen buttons,
/// three padding bits, in range, one padding bit, X and Y to 32767, pressure
/// to 16383, and two signed tilt bytes. Plus a mouse report the parser must
/// leave out.
final _penAndMouse = _hex(
  // Digitizer, Pen, Application, Report ID 9, Stylus, Physical
  '05 0D 09 02 A1 01 85 09 09 20 A1 00 '
  // Tip, Barrel, Eraser: 3 bits
  '09 42 09 44 09 45 15 00 25 01 75 01 95 03 81 02 '
  // 3 constant bits
  '95 03 81 03 '
  // In Range: 1 bit, then 1 constant bit
  '09 32 95 01 81 02 95 01 81 03 '
  // X and Y, 16 bits each, 0 to 32767
  '05 01 09 30 26 FF 7F 75 10 95 01 81 02 09 31 81 02 '
  // Tip pressure, 0 to 16383
  '05 0D 09 30 26 FF 3F 81 02 '
  // X tilt and Y tilt, signed bytes
  '09 3D 09 3E 15 81 25 7F 75 08 95 02 81 02 '
  'C0 C0 '
  // Mouse, Report ID 3: buttons and relative X, Y
  '05 01 09 02 A1 01 85 03 09 01 A1 00 05 09 19 01 29 03 15 00 25 01 '
  '75 01 95 03 81 02 95 05 81 03 05 01 09 30 09 31 15 81 25 7F 75 08 '
  '95 02 81 06 C0 C0',
);

/// A lower resolution pen report like Report ID 5: tip, barrel, in range
/// and padding, then X and Y to 4095 and pressure to 2047.
final _lowRes = _hex(
  '05 0D 09 02 A1 01 85 05 09 20 A1 00 '
  '09 42 09 44 15 00 25 01 75 01 95 02 81 02 '
  '95 02 81 03 09 32 95 01 81 02 95 03 81 03 '
  '05 01 09 30 15 00 26 FF 0F 75 10 95 01 81 02 09 31 81 02 '
  '05 0D 09 30 26 FF 07 81 02 C0 C0',
);

void main() {
  test('finds the pen report and leaves the mouse out', () {
    final layouts = penLayoutsFrom(_penAndMouse);
    expect(layouts, hasLength(1));
    final pen = layouts.single;
    expect(pen.reportId, 9);
    expect(pen.x.logicalMax, 32767);
    expect(pen.pressure!.logicalMax, 16383);
    expect(pen.tiltX!.logicalMin, -127);
    expect(pen.inRange!.bitOffset, 6);
    expect(pen.x.bitOffset, 8);
  });

  test(
    'reads the two captured T605 samples the same way the fixed parser does',
    () {
      final pen = penLayoutsFrom(_penAndMouse).single;
      final hover = readPen(pen, _hex('09c0fe3d505c1d00e3e5'))!;
      expect(hover.tip, isFalse);
      expect(hover.inRange, isTrue);
      expect(hover.x, closeTo(15870 / 32767, 1e-9));
      expect(hover.y, closeTo(23632 / 32767, 1e-9));
      expect(hover.pressure, closeTo(29 / 16383, 1e-9));
      expect(hover.tiltX, -29);
      expect(hover.tiltY, -27);

      final touch = readPen(pen, _hex('09c1b837334d9505aefb'))!;
      expect(touch.tip, isTrue);
      expect(touch.x, closeTo(14264 / 32767, 1e-9));
      expect(touch.pressure, closeTo(1429 / 16383, 1e-9));
      expect(touch.tiltX, -82);
      expect(touch.tiltY, -5);
    },
  );

  test('reads a lower resolution pen report on its own scale', () {
    final pen = penLayoutsFrom(_lowRes).single;
    expect(pen.reportId, 5);
    expect(pen.x.logicalMax, 4095);
    expect(pen.pressure!.logicalMax, 2047);
    // tip and in range set, X 4095, Y 2048, pressure 1024
    final reading = readPen(pen, _hex('05 11 FF 0F 00 08 00 04'))!;
    expect(reading.tip, isTrue);
    expect(reading.inRange, isTrue);
    expect(reading.x, closeTo(1, 1e-9));
    expect(reading.y, closeTo(2048 / 4095, 1e-9));
    expect(reading.pressure, closeTo(1024 / 2047, 1e-9));
  });

  test('a transfer with another report id or too few bytes is not read', () {
    final pen = penLayoutsFrom(_penAndMouse).single;
    expect(readPen(pen, _hex('03 01 05 05')), isNull);
    expect(readPen(pen, _hex('09 c1 b8')), isNull);
    expect(readPen(pen, Uint8List(0)), isNull);
  });

  test('a two-byte maximum like FF FF reads as unsigned', () {
    final layouts = penLayoutsFrom(
      _hex(
        '05 0D 09 02 A1 01 85 07 09 42 15 00 25 01 75 01 95 01 81 02 '
        '95 07 81 03 05 01 09 30 26 FF FF 75 10 95 01 81 02 09 31 81 02 C0',
      ),
    );
    expect(layouts.single.x.logicalMax, 65535);
  });

  test('never throws on damaged or random descriptors', () {
    expect(penLayoutsFrom(Uint8List(0)), isEmpty);
    expect(penLayoutsFrom(_hex('05')), isEmpty);
    final cut = Uint8List.sublistView(_penAndMouse, 0, 40);
    penLayoutsFrom(cut);
    var seed = 7;
    for (var n = 0; n < 500; n++) {
      final bytes = Uint8List.fromList([
        for (var i = 0; i < 64; i++)
          (seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF) & 0xFF,
      ]);
      final layouts = penLayoutsFrom(bytes);
      for (final layout in layouts) {
        readPen(layout, bytes);
      }
    }
  });
}
