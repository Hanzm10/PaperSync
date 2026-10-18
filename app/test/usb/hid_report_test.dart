import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/usb/hid_report.dart';
import 'package:papersync/usb/tablet_profile.dart';

Uint8List _hex(String hex) {
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

void main() {
  group('parsePenReport', () {
    test('decodes the hovering capture', () {
      final report = parsePenReport(_hex('09c0fe3d505c1d00e3e5'))!;
      expect(report.tip, isFalse);
      expect(report.inRange, isTrue);
      expect(report.x, 15870);
      expect(report.y, 23632);
      expect(report.pressure, 29);
      expect(report.tiltX, -29);
      expect(report.tiltY, -27);
    });

    test('decodes the touching capture', () {
      final report = parsePenReport(_hex('09c1b837334d9505aefb'))!;
      expect(report.tip, isTrue);
      expect(report.inRange, isTrue);
      expect(report.x, 14264);
      expect(report.y, 19763);
      expect(report.pressure, 1429);
      expect(report.tiltX, -82);
      expect(report.tiltY, -5);
    });

    test('ignores the constant bit 7 and bits 3 to 5', () {
      final withPadding = parsePenReport(
        _hex(
          '09b8000000000000'
          '0000',
        ),
      )!;
      expect(withPadding.tip, isFalse);
      expect(withPadding.barrel, isFalse);
      expect(withPadding.eraser, isFalse);
      expect(withPadding.inRange, isFalse);
    });

    test('reads the barrel and eraser bits', () {
      final barrel = parsePenReport(
        _hex(
          '09c2000000000000'
          '0000',
        ),
      )!;
      final eraser = parsePenReport(
        _hex(
          '09c4000000000000'
          '0000',
        ),
      )!;
      expect(barrel.barrel, isTrue);
      expect(barrel.eraser, isFalse);
      expect(eraser.eraser, isTrue);
      expect(eraser.barrel, isFalse);
    });

    test('clamps values above the logical range', () {
      final report = parsePenReport(
        _hex(
          '09c1ffffffffffff'
          '7f80',
        ),
      )!;
      expect(report.x, penMaxCoordinate);
      expect(report.y, penMaxCoordinate);
      expect(report.pressure, penMaxPressure);
      expect(report.tiltX, 127);
      expect(report.tiltY, -128);
    });

    test('drops other report ids and wrong lengths', () {
      expect(parsePenReport(_hex('05c0fe3d505c1d00e3e5')), isNull);
      expect(parsePenReport(_hex('03c0fe3d505c1d00e3e5')), isNull);
      expect(parsePenReport(_hex('09c0fe3d505c1d00e3')), isNull);
      expect(parsePenReport(_hex('09c0fe3d505c1d00e3e5ff')), isNull);
      expect(parsePenReport(Uint8List(0)), isNull);
    });

    test('never throws on random bytes', () {
      final random = Random(7);
      for (var i = 0; i < 2000; i++) {
        final bytes = Uint8List.fromList([
          for (var j = 0; j < random.nextInt(20); j++) random.nextInt(256),
        ]);
        parsePenReport(bytes);
      }
    });
  });

  group('TabletProfile', () {
    test('identifies the Lumispark T605', () {
      expect(tabletProfileFor(0x08F2, 0x6811), same(lumisparkT605));
      expect(tabletProfileFor(0x08F2, 0x0001), isNull);
      expect(tabletProfileFor(0x1234, 0x6811), isNull);
    });

    test('uses the measured range of the T605', () {
      expect(lumisparkT605.xMin, 0);
      expect(lumisparkT605.xMax, 32759);
      expect(lumisparkT605.yMin, 0);
      expect(lumisparkT605.yMax, 32759);
      expect(lumisparkT605.xMm(0), 0);
      expect(lumisparkT605.xMm(32759), closeTo(170, 1e-9));
      expect(lumisparkT605.yMm(32759), closeTo(107, 1e-9));
    });

    test('scales the two axes separately', () {
      // The same raw value is further across X than down Y.
      expect(lumisparkT605.xMm(16380), closeTo(85, 0.01));
      expect(lumisparkT605.yMm(16380), closeTo(53.5, 0.01));
      expect(
        lumisparkT605.xMm(10000) / lumisparkT605.yMm(10000),
        closeTo(170 / 107, 1e-9),
      );
    });

    test('puts the origin at the top left with no flip', () {
      // The printed corner marks, pressed with the pen tip.
      expect(lumisparkT605.xMm(138), closeTo(0.72, 0.01));
      expect(lumisparkT605.yMm(147), closeTo(0.48, 0.01));
      expect(lumisparkT605.xMm(32253), closeTo(167.4, 0.1));
      expect(lumisparkT605.yMm(32759), closeTo(107, 1e-9));
      // X grows to the right and Y grows downward.
      expect(lumisparkT605.xMm(20000), greaterThan(lumisparkT605.xMm(10000)));
      expect(lumisparkT605.yMm(20000), greaterThan(lumisparkT605.yMm(10000)));
    });

    test('an unmeasured tablet falls back to the full logical range', () {
      const other = TabletProfile(name: 'Other', vendorId: 1, productId: 2);
      expect(other.xMax, 32767);
      expect(other.xMm(32767), closeTo(170, 1e-9));
    });

    test('uses measured corners for each axis separately', () {
      final measured = lumisparkT605.withCorners(
        xMin: 1000,
        xMax: 31000,
        yMin: 500,
        yMax: 20500,
      );
      expect(measured.xMm(1000), 0);
      expect(measured.xMm(31000), closeTo(170, 1e-9));
      expect(measured.yMm(500), 0);
      expect(measured.yMm(20500), closeTo(107, 1e-9));
      expect(measured.yMm(10500), closeTo(53.5, 1e-9));
    });

    test('keeps points outside the corners inside the area', () {
      final measured = lumisparkT605.withCorners(
        xMin: 1000,
        xMax: 31000,
        yMin: 500,
        yMax: 20500,
      );
      expect(measured.xMm(0), 0);
      expect(measured.xMm(32767), 170);
      expect(measured.yMm(30000), 107);
    });
  });
}
